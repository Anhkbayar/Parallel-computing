const http = require('http');
const fs = require('fs');
const { Server } = require('socket.io');

const PORT = 8002;
const PEER_PORT = 8001;

const server = http.createServer((req, res) => {
    if (req.method === 'POST' && req.url === '/forward') {
        let body = '';

        req.on('data', chunk => {
            body += chunk.toString();
        });

        req.on('end', () => {
            const data = JSON.parse(body);

            io.emit('push', "[From A] " + data.message);

            res.writeHead(200);
            res.end("ok");
        });

        return;
    }

    fs.readFile('client.html', (err, data) => {
        if (err) {
            res.writeHead(500);
            res.end('Error');
            return;
        }
        res.writeHead(200, { 'Content-type': 'text/html' });
        res.end(data);
    });
});

const io = new Server(server);

io.on('connection', (socket) => {
    console.log('Client connected to B');

    const clientId = socket.handshake.query.clientId || socket.id;

    clients[socket.id] = clientId;

    io.emit('clients', Object.values(clients));

    socket.on('send', (data) => {
        console.log('B received:', data);

        io.emit('push', "[B] " + data);

        const postData = JSON.stringify({ message: data });

        const options = {
            hostname: 'localhost',
            port: PEER_PORT,
            path: '/forward',
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(postData)
            }
        };

        const req = http.request(options);
        req.on('error', () => {
            console.log("Server A is down");
        });

        req.write(postData);
        req.end();
    });

    socket.on('disconnect', () => {
        console.log('Client disconnected from B');

        delete clients[socket.id];

        io.emit('clients', Object.values(clients));
    });
});

server.listen(PORT, () => {
    console.log(`Server B running at http://localhost:${PORT}`);
});