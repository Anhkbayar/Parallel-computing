const http = require("http");
const { Server } = require("socket.io");
const { io: ClientIO } = require("socket.io-client");

const BALANCER_PORT = 8000;
const SERVERS = {
    A: { url: "http://localhost:8001", port: 8001 },
    B: { url: "http://localhost:8002", port: 8002 },
};
const HEALTH_INTERVAL_MS = 5000;
const HEALTH_TIMEOUT_MS = 2000;

//State
const serverStatus = { A: false, B: false };
const serverSockets = { A: null, B: null };

// socketId → { socketId, clientId, assignedServer, preferredServer, socket }
const clients = new Map();

// Bounded message dedup
const MAX_SEEN = 5000;
const seenMessages = new Set();
function addSeen(id) {
    if (seenMessages.size >= MAX_SEEN)
        seenMessages.delete(seenMessages.values().next().value);
    seenMessages.add(id);
}

//HTTP/ health check
const httpServer = http.createServer((req, res) => {
    res.setHeader("Access-Control-Allow-Origin", "*");
    if (req.url === "/health") {
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({
            status: "UP",
            servers: serverStatus,
            clientCount: clients.size,
            clients: Array.from(clients.values()).map(c => ({
                clientId: c.clientId,
                assignedServer: c.assignedServer,
                preferredServer: c.preferredServer,
            })),
        }));
        return;
    }
    res.writeHead(404); res.end("Not found");
});

const io = new Server(httpServer, { cors: { origin: "*" } });

//Backend connection
function connectToBackend(name) {
    const { url } = SERVERS[name];
    const socket = ClientIO(url, {
        reconnection: true,
        reconnectionAttempts: Infinity,
        reconnectionDelay: 2000,
    });

    socket.on("connect", () => {
        serverStatus[name] = true;
        console.log(`[Balancer] Server ${name} connected`);
        reregisterClientsOn(name); // re-register clients still assigned here
        failbackClientsTo(name);
    });

    socket.on("disconnect", () => {
        serverStatus[name] = false;
        console.log(`[Balancer] Server ${name} disconnected`);
        rerouteClientsFrom(name);
    });

    socket.on("connect_error", () => { serverStatus[name] = false; });

    // Receive broadcasts from backend → forward to all balancer clients (deduped)
    socket.on("message", (msg) => {
        if (seenMessages.has(msg.messageId)) return;
        addSeen(msg.messageId);
        console.log(`[Balancer] [Server ${name}] ${msg.fromClientId}: ${msg.text}`);
        io.emit("message", msg);
    });

    serverSockets[name] = socket;
}

//Route helper
function preferredServerFor(clientId) {
    const num = parseInt(clientId, 10);
    return isNaN(num) ? "A" : num % 2 === 0 ? "A" : "B";
}

function availableServer(preferred) {
    if (serverStatus[preferred]) return preferred;
    const fallback = preferred === "A" ? "B" : "A";
    if (serverStatus[fallback]) return fallback;
    return null; // both down
}

//Fault handling
function rerouteClientsFrom(failedServer) {
    const fallback = failedServer === "A" ? "B" : "A";
    if (!serverStatus[fallback]) {
        console.log(`[Balancer] Both servers are DOWN`);
        io.emit("all_servers_down", { message: "All servers are down. Please wait." });
        return;
    }

    let count = 0;
    for (const client of clients.values()) {
        if (client.assignedServer === failedServer) {
            client.assignedServer = fallback;
            // Register client on the fallback backend
            serverSockets[fallback].emit("register_client", { clientId: client.clientId });
            client.socket.emit("server_switched", {
                from: failedServer,
                to: fallback,
                message: `Server ${failedServer} went down → switched to Server ${fallback}`,
            });
            count++;
        }
    }
    if (count > 0)
        console.log(`[Balancer] Rerouted ${count} client(s): ${failedServer} → ${fallback}`);
}

function reregisterClientsOn(serverName) {
    let count = 0;
    for (const client of clients.values()) {
        if (client.assignedServer === serverName) {
            serverSockets[serverName].emit("register_client", { clientId: client.clientId });
            count++;
        }
    }
    if (count > 0)
        console.log(`[Balancer]Re-registered ${count} client(s) on Server ${serverName}`);
}

//Client connections
io.on("connection", (socket) => {
    console.log(`[Balancer] New connection: ${socket.id}`);

    socket.on("register_client", (data) => {
        const { clientId } = data;
        const preferred = preferredServerFor(clientId);
        const assigned = availableServer(preferred);

        if (!assigned) {
            socket.emit("error_event", { message: "All servers are down. Please try again later." });
            console.log(`[Balancer] No server available for client ${clientId}`);
            return;
        }

        clients.set(socket.id, {
            socketId: socket.id,
            clientId,
            assignedServer: assigned,
            preferredServer: preferred,
            socket,
        });

        // Register on backend
        serverSockets[assigned].emit("register_client", { clientId });

        const note = assigned !== preferred
            ? `Server ${preferred} unavailable → assigned to Server ${assigned}`
            : null;

        socket.emit("registered", {
            clientId,
            server: assigned,
            port: SERVERS[assigned].port,
            note,
        });

        console.log(`[Balancer] Client ${clientId} → Server ${assigned}` +
            (note ? ` (fallback, preferred: ${preferred})` : ""));
    });

    socket.on("message", (data) => {
        const client = clients.get(socket.id);
        if (!client) {
            socket.emit("error_event", { message: "Not registered. Reconnect and register first." });
            return;
        }

        const target = availableServer(client.assignedServer);
        if (!target) {
            socket.emit("error_event", { message: "All servers are down. Message not delivered." });
            return;
        }

        // Dynamic reroute on the fly if assigned server just went down
        if (target !== client.assignedServer) {
            const old = client.assignedServer;
            client.assignedServer = target;
            socket.emit("server_switched", {
                from: old,
                to: target,
                message: `Server ${old} unavailable → switched to Server ${target}`,
            });
        }

        serverSockets[target].emit("message", data);
    });

    socket.on("disconnect", () => {
        const client = clients.get(socket.id);
        if (client) console.log(`[Balancer] Client ${client.clientId} disconnected`);
        clients.delete(socket.id);
    });
});

function failbackClientsTo(restoredServer) {
    if (!serverStatus[restoredServer]) return;

    let count = 0;

    for (const client of clients.values()) {
        // Only move clients whose preferred server is restoredServer
        // and who are currently using fallback server
        if (
            client.preferredServer === restoredServer &&
            client.assignedServer !== restoredServer
        ) {
            const old = client.assignedServer;

            client.assignedServer = restoredServer;

            serverSockets[restoredServer].emit("register_client", {
                clientId: client.clientId,
            });

            client.socket.emit("server_switched", {
                from: old,
                to: restoredServer,
                message: `Server ${restoredServer} is back UP → switched back to preferred Server ${restoredServer}`,
            });

            count++;
        }
    }

    if (count > 0) {
        console.log(`[Balancer] Failed back ${count} client(s) to Server ${restoredServer}`);
    }
}

//Active health polling
async function pollHealth() {
    for (const [name, { url }] of Object.entries(SERVERS)) {
        const wasUp = serverStatus[name];
        let isUp = false;

        try {
            const res = await fetch(`${url}/health`, {
                signal: AbortSignal.timeout(HEALTH_TIMEOUT_MS),
            });
            const data = await res.json();
            isUp = data.status === "UP";
        } catch {
            isUp = false;
        }

        if (!wasUp && isUp) {
            serverStatus[name] = true;
            console.log(`[Balancer] Server ${name} is back UP`);
            reregisterClientsOn(name);
        } else if (wasUp && !isUp) {
            serverStatus[name] = false;
            console.log(`[Balancer] Server ${name} went DOWN (health check)`);
            rerouteClientsFrom(name);
        }
    }
}

setInterval(pollHealth, HEALTH_INTERVAL_MS);

httpServer.listen(BALANCER_PORT, () => {
    console.log(`Running on port ${BALANCER_PORT}`);
    console.log(`Routing: even clientId → A, odd clientId → B`);
    connectToBackend("A");
    connectToBackend("B");
});