//server.js
const http = require('http');
const fs = require('fs'); //filesystem

const server = http.createServer((req, res)=>{
    fs.readFile('client.html', (err, data)=>{
        if(err){
            res.writeHead(500, {'Content-type':'text/html'});
            res.end('Error');
            return;
        }
        res.writeHead(200, {'Content-type':'text/html'});
        res.end(data);
    });
});

const io = require('socket.io')(server);

io.on('connection', (socket)=>{
    console.log('Node connected');

    socket.on('send', (data)=>{
        io.emit('push', data);
    });

    socket.on('disconnect', ()=>{
        console.log("Node disconnected");
    })
});

server.listen(6769, ()=>{
    console.log('http://localhost:6769');
});