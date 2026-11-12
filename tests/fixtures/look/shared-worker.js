// A shared worker that writes once for each page that connects to it.
onconnect = event => {
  const port = event.ports[0];
  fetch('/from-shared-worker', {method: 'POST', body: 'x=1'})
    .then(r => port.postMessage('sent ' + r.status), () => port.postMessage('rejected'));
};
