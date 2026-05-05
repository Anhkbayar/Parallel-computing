const http = require("http");
const { Server } = require("socket.io");
const { io: ClientIO } = require("socket.io-client");

const serverName = process.argv[2]; // A or B
const port = Number(process.argv[3]); // 8001 or 8002
const peerUrl = process.argv[4]; // http://localhost:8002 or http://localhost:8001

if (!serverName || !port || !peerUrl) {
  console.log("Usage: node server.js <A|B> <port> <peerUrl>");
  process.exit(1);
}

const MAX_SEEN = 5000;
const seenMessages = new Set();

function addSeen(id) {
  if (seenMessages.size >= MAX_SEEN) {
    seenMessages.delete(seenMessages.values().next().value);
  }
  seenMessages.add(id);
}

//State
const clients = new Map();   // socketId → { socketId, clientId, server }
let peerSocket = null;
let peerConnected = false;
const peerName = serverName === "A" ? "B" : "A";

//HTTP server (health endpoint)
const httpServer = http.createServer((req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") { res.writeHead(204); res.end(); return; }

  if (req.url === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({
      status: "UP",
      server: serverName,
      port,
      clientCount: clients.size,
      clients: Array.from(clients.values()),
      peerConnected,
      peerName,
    }));
    return;
  }

  res.writeHead(404, { "Content-Type": "text/plain" });
  res.end("Not found");
});

//Socket.IO server
const io = new Server(httpServer, { cors: { origin: "*" } });

function createId() {
  return `${Date.now()}-${Math.random().toString(36).substring(2, 12)}`;
}

function broadcastClientList() {
  io.emit("client_list", Array.from(clients.values()));
}

//Peer connection (inter-server)
function connectToPeer() {
  peerSocket = ClientIO(peerUrl, {
    reconnection: true,
    reconnectionAttempts: Infinity,
    reconnectionDelay: 2000,
  });

  peerSocket.on("connect", () => {
    peerConnected = true;
    console.log(`[Server ${serverName}] Peer ${peerName} connected`);
    peerSocket.emit("server_register", { serverName, port });
  });

  peerSocket.on("disconnect", () => {
    peerConnected = false;
    console.log(`[Server ${serverName}] Peer ${peerName} disconnected`);
  });

  peerSocket.on("connect_error", () => {
    peerConnected = false;
  });

  // Receive message forwarded from peer server
  peerSocket.on("server_message", (message) => {
    if (seenMessages.has(message.messageId)) return;
    addSeen(message.messageId);
    console.log(`[Server ${serverName}] Peer msg — ${message.fromClientId}: ${message.text}`);
    io.emit("message", message);
  });
}

function forwardToPeer(message) {
  if (!peerConnected || !peerSocket) {
    console.log(`[Server ${serverName}] Peer unavailable — message stays local`);
    return;
  }
  peerSocket.emit("server_message", message);
}

//Client connections
io.on("connection", (socket) => {
  console.log(`[Server ${serverName}] Socket connected: ${socket.id}`);

  socket.on("register_client", (data) => {
    clients.set(socket.id, {
      socketId: socket.id,
      clientId: data.clientId,
      server: serverName,
    });
    console.log(`[Server ${serverName}] Client ${data.clientId} registered`);
    socket.emit("registered", { clientId: data.clientId, server: serverName, port });
    broadcastClientList();
  });

  socket.on("message", (data) => {
    const message = {
      messageId: data.messageId || createId(),
      fromClientId: data.fromClientId,
      text: data.text,
      originServer: serverName,
      timestamp: new Date().toISOString(),
    };

    if (seenMessages.has(message.messageId)) return;
    addSeen(message.messageId);

    console.log(`[Server ${serverName}] {message.fromClientId}: ${message.text}`);

    // 1. Broadcast to all local clients
    io.emit("message", message);
    // 2. Forward to peer server
    forwardToPeer(message);
  });

  socket.on("server_register", (data) => {
    console.log(`[Server ${serverName}] Peer registered: Server ${data.serverName}`);
  });

  socket.on("disconnect", () => {
    const client = clients.get(socket.id);
    if (client) console.log(`[Server ${serverName}] Client ${client.clientId} disconnected`);
    clients.delete(socket.id);
    broadcastClientList();
  });
});

httpServer.listen(port, () => {
  console.log(`[Server ${serverName}] Running on port ${port}`);
  connectToPeer();
});