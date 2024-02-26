const net = require('net');
const path = require('path');
const process = require('process');

const port = Number(process.argv[2]);

function handle() {
    const toJSON = (obj) => JSON.stringify(obj) + '\n';
    const run = (file) => toJSON({ type: 'run', content: file });
    const close = (file) => toJSON({ type: 'close', content: file || '' });
    const stop = () => toJSON({ type: 'stop', content: '' });
    const isopen = (file) => toJSON({ type: 'isopen', content: file });
    const isready = () => toJSON({ type: 'isready', content: '' });

    const notebook = (arg) => {
        if (arg) {
            return path.join(process.cwd(), arg);
        }
        throw new Error('No notebook specified.');
    }

    const type = process.argv[3];
    const arg = process.argv[4];

    switch (type) {
        case 'run':
            return run(notebook(arg));
        case 'close':
            return close(notebook(arg));
        case 'stop':
            return stop();
        case 'isopen':
            return isopen(notebook(arg));
        case 'isready':
            return isready();
        default:
            throw new Error('Invalid command.');
    }
}

const debug = false;

const client = new net.Socket();
client.connect(port, '127.0.0.1', function () {
    debug && console.log('Connected');
    client.write(handle());
});
client.on('data', function (data) {
    console.log(debug ? JSON.parse(data.toString()) : data.toString());
    client.destroy();
});
client.on('close', function () {
    debug && console.log('Connection closed');
});
