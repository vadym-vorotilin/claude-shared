// A dedicated worker that writes as soon as it starts.
fetch('/from-worker', {method: 'POST', body: 'x=1'})
  .then(r => postMessage('sent ' + r.status), () => postMessage('rejected'));
