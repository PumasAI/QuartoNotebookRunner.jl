const net = require('net');
const path = require('path');
const process = require('process');
const crypto = require('crypto');

const port = Number(process.argv[2]);
const key = process.argv[3];

function handle() {
    const toJSON = (obj) => {
        payload = JSON.stringify(obj);
        const hmac = crypto.createHmac('sha256', key);
        hmac.update(payload);
        const hmac_b64 = hmac.digest('base64');
        return JSON.stringify({hmac: hmac_b64, payload}) + '\n';
    }
    const run = (file) => toJSON({ type: 'run', content: file });
    const close = (file) => toJSON({ type: 'close', content: file || '' });
    const stop = () => toJSON({ type: 'stop', content: '' });
    const isopen = (file) => toJSON({ type: 'isopen', content: file });
    const isready = () => toJSON({ type: 'isready', content: '' });
    const status = () => toJSON({ type: 'status', content: '' });

    const notebook = (arg) => {
        if (path.isAbsolute(arg)) {
            return arg
        }
        throw new Error('No notebook with absolute path specified.');
    }

    const type = process.argv[4];
    const arg = process.argv[5];

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
        case 'status':
            return status();
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

// for `run` messages, the server will return multiple responses,
// but even for single responses, the 'data' callback might be called
// multiple times with fragments, so we handle each full response
// only after our data contains a linebreak
let restOfData = "";
client.on('data', function (data) {
    restOfData += data.toString();
    while (true) {
        const linebreakAt = restOfData.indexOf("\n");
        if (linebreakAt === -1) {
            // handle complete data in a later call
            break
        }
        const message = restOfData.substring(0, linebreakAt);
        restOfData = restOfData.substring(linebreakAt + 1);
        const d = JSON.parse(message);
        if (d.type !== 'progress_update') {
            console.log(debug ? d : message);
            client.destroy();
            break
        }
    }
});
client.on('close', function () {
    debug && console.log('Connection closed');
});
client.on('error', function (err) {
    const type = process.argv[4];
    if (type == 'stop' && err.code == 'ECONNRESET'){
        debug && console.log('Connection was reset after sending the stop command.')
    } else {
        throw err;
    }
});
