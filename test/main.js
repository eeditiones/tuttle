import { before, after } from 'node:test';
// the tests depend on eachother. run the in the correct order.
import github from './github.js';
import gitlab from './gitlab.js';
import tuttle from './tuttle.js';
import { ensureTuttleIsInstalled, remove } from './util.js';

before(ensureTuttleIsInstalled);

await github();
await gitlab();
await tuttle();

after(() => remove());
