import assert from 'node:assert';
import {
    auth,
    axios,
    ensureTuttleIsInstalled,
    getResource,
    install,
    putResource,
    remove,
} from './util.js';
import { before, describe, it } from 'node:test';
import { readFile } from 'node:fs/promises';

import { DOMParser } from 'slimdom';

export default () =>
    describe('Tuttle', async function () {
        before(async () => {
            await ensureTuttleIsInstalled();
        });
        const defaultCollection = 'tuttle-sample-data';

        describe('git/status', async function () {
            let repos, defaultRepo
            before(async () => {
                const resultPromise = axios.get('git/status', { auth });
                await assert.doesNotReject(resultPromise, 'The request should succeed');
                const res = await resultPromise;
                repos = res.data.repos;
                defaultRepo = res.data.default;
            })

            it('returns status 200', async function () {
                assert.strictEqual(res.status, 200);
            });

            it('default repo', async function () {
                assert.ok(defaultRepo);
                assert.strictEqual(defaultRepo, defaultCollection);
            });

            it('lists repos', async function () {
                assert.ok(repos);
                assert(repos.length > 0);
            });

            it('github sample repo is up to date', async function () {
                assert.deepStrictEqual(repos[0], {
                    baseurl: 'https://api.github.com/',
                    collection: defaultCollection,
                    deployed: '5006b2cd6552e2b09ba94d597cf89c100de3399e',
                    hookuser: 'admin',
                    message: 'remote found',
                    owner: 'eeditiones',
                    path: `/db/apps/${defaultCollection}`,
                    'project-id': null,
                    ref: 'next',
                    remote: '5006b2cd6552e2b09ba94d597cf89c100de3399e',
                    repo: 'tuttle-sample-data',
                    status: 'uptodate',
                    url: 'https://github.com/eeditiones/tuttle-sample-data',
                    type: 'github',
                });
            });

            it('gitlab sample repo is not authorized', async function () {
                assert.deepStrictEqual(repos[1], {
                    baseurl: 'https://gitlab.com/api/v4/',
                    collection: 'tuttle-sample-gitlab',
                    deployed: 'd80c71f0ac63d355f1583cfe2777fe3dcde4d8bc',
                    hookuser: 'admin',
                    message: 'remote found',
                    owner: 'line-o',
                    path: '/db/apps/tuttle-sample-gitlab',
                    'project-id': '50872175',
                    ref: 'main',
                    remote: 'd80c71f0ac63d355f1583cfe2777fe3dcde4d8bc',
                    repo: 'tuttle-sample-data',
                    status: 'uptodate',
                    type: 'gitlab',
                    url: 'https://gitlab.com/line-o/tuttle-sample-data.git',
                    type: 'gitlab',
                });
            });
        });

        describe('git/lockfile', async function () {
            let res
            before(async () => {
                const resultPromise = axios.get('git/lockfile', { auth });
                await assert.doesNotReject(resultPromise, 'The request should succeed');
                res = await resultPromise;
            });

            it('returns status 200', async function () {
                assert.strictEqual(res.status, 200);
            });

            it('confirms no lockfile to be present', async function () {
                assert.strictEqual(
                    res.data.message,
                    `No lockfile for '${defaultCollection}' found.`,
                );
            });
        });

        describe(`git/${defaultCollection}/lockfile`, async function () {
            let res
            before(async () => {
                const resultPromise = axios.get(`git/${defaultCollection}/lockfile`, { auth });
                await assert.doesNotReject(resultPromise, 'The request should succeed');
                res = await resultPromise;
            })
            
            it('returns status 200', async function () {
                assert.strictEqual(res.status, 200);
            });

            it('confirms no lockfile to be present', async function () {
                assert.strictEqual(
                    res.data.message,
                    `No lockfile for '${defaultCollection}' found.`,
                );
            });
        });

        describe('git/status with different settings', async function () {
            let repos,res
            before(async () => {
                const buffer = await readFile('./test/fixtures/alt-tuttle.xml');
                await putResource(buffer, '/db/apps/tuttle/data/tuttle.xml');
                const buffer2 = await readFile('./test/fixtures/test.xqm');
                await putResource(buffer2, '/db/apps/tuttle/modules/test.xqm');

                const resultPromise = axios.get('git/status', { auth });
                await assert.doesNotReject(resultPromise, 'The request should succeed');
                res = await resultPromise;
                repos = res.data.repos;
            })

            it('returns status 200', async function () {
                assert.strictEqual(res.status, 200);
            });

            it('lists repos', async function () {
                assert.ok(repos);
                assert(repos.length > 0);
            });

            it('has no default repo', async function () {
                assert.strictEqual(res.data.default, null);
            });

            it('ref "nonexistent" cannot be found in github sample repo ', async function () {
                    // const resultPromise = axios.get('git/status', { auth });
                    // await assert.doesNotReject(resultPromise, 'The request should succeed');
                    // const res = await resultPromise;
                    // const repos = res.data.repos;

                assert.deepStrictEqual(repos[0], {
                    baseurl: 'https://api.github.com/',
                    collection: 'tuttle-sample-data',
                    deployed: '5006b2cd6552e2b09ba94d597cf89c100de3399e',
                    hookuser: 'admin',
                    message: 'server connection failed: Not Found (404)',
                    owner: 'eeditiones',
                    path: '/db/apps/tuttle-sample-data',
                    'project-id': null,
                    ref: 'nonexistent',
                    repo: 'tuttle-sample-data',
                    status: 'error',
                    type: 'github',
                });
            });
        });

        it('can also write hashes to repo.xml', async () => {
            await remove();
            await install();
        
            // Set up tuttle with a repo where repo.xml is used to store the git sha info
            const buffer = await readFile('./test/fixtures/alt-repoxml-tuttle.xml');
            await putResource(buffer, '/db/apps/tuttle/data/tuttle.xml');
        
            const resultPromise = axios.get('git/status', { auth });
            await assert.doesNotReject(resultPromise);
        
            const stagingPromise = axios.get(`git/tuttle-sample-data`, {}, { auth });
            await assert.doesNotReject(stagingPromise, 'The request should succeed');
        
            const deployPromise = axios.post(`git/tuttle-sample-data`, {}, { auth });
            await assert.doesNotReject(deployPromise, 'The request should succeed');
        
            const repoXML = await getResource('/db/apps/tuttle-sample-data/repo.xml');
        
            const repo = new DOMParser().parseFromString(repoXML.toString(), 'text/xml').documentElement;
            assert.ok(repo.getAttribute('commit-id'), 'The commit id should be set');
            assert.ok(repo.getAttribute('commit-time'), 'The commit time should be set');
            assert.ok(repo.getAttribute('commit-dateTime'), 'The commit dateTime should be set');
        });
        
    });

