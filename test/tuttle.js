import assert from 'node:assert';
import { auth, axios, putResource, ensureTuttleIsInstalled } from './util.js';
import { readFile } from 'node:fs/promises';
import { before, describe, it } from 'node:test';

export default describe('Tuttle', function () {
    before(async () => {
        await ensureTuttleIsInstalled();
    });
    const defaultCollection = 'tuttle-sample-data';

    describe('git/status', function () {
        let res, repos, defaultRepo;

        before(async function () {
            res = await axios.get('git/status', { auth });
            repos = res.data.repos;
            defaultRepo = res.data.default;
        });

        it('returns status 200', function () {
            assert.strictEqual(res.status, 200);
        });

        it('default repo', function () {
            assert.ok(defaultRepo);
            assert.strictEqual(defaultRepo, defaultCollection);
        });

        it('lists repos', function () {
            assert.ok(repos);
            assert(repos.length > 0);
        });

        it('github sample repo is up to date', function () {
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
                remote: '5006b2c',
                repo: 'tuttle-sample-data',
                status: 'uptodate',
                url: 'https://github.com/eeditiones/tuttle-sample-data',
                type: 'github',
            });
        });

        it('gitlab sample repo is not authorized', function () {
            assert.deepStrictEqual(repos[1], {
                baseurl: 'https://gitlab.com/api/v4/',
                collection: 'tuttle-sample-gitlab',
                deployed: 'd80c71f',
                hookuser: 'admin',
                message: 'remote found',
                owner: 'line-o',
                path: '/db/apps/tuttle-sample-gitlab',
                'project-id': '50872175',
                ref: 'main',
                remote: 'd80c71f',
                repo: 'tuttle-sample-data',
                status: 'uptodate',
                type: 'gitlab',
                url: 'https://gitlab.com/line-o/tuttle-sample-data.git',
                type: 'gitlab',
            });
        });
    });

    describe('git/lockfile', function () {
        let res;
        before(async function () {
            res = await axios.get('git/lockfile', { auth });
        });

        it('returns status 200', function () {
            assert.strictEqual(res.status, 200);
        });

        it('confirms no lockfile to be present', function () {
            assert.strictEqual(res.message, `No lockfile for '${defaultCollection}' found.`);
        });
    });

    describe(`git/${defaultCollection}/lockfile`, function () {
        let res;
        before(async function () {
            res = await axios.get(`git/${defaultCollection}/lockfile`, { auth });
        });

        it('returns status 200', function () {
            assert.strictEqual(res.status, 200);
        });

        it('confirms no lockfile to be present', function () {
            assert.strictEqual(res.message, `No lockfile for '${defaultCollection}' found.`);
        });
    });

    describe('git/status with different settings', function () {
        let res, repos;

        it('github sample repo is up to date', function () {
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
                remote: '5006b2c',
                repo: 'tuttle-sample-data',
                status: 'uptodate',
                url: 'https://github.com/eeditiones/tuttle-sample-data',
                type: 'github',
            });
        });

        it('returns status 200', function () {
            assert.strictEqual(res.status, 200);
        });

        it('has no default repo', function () {
            assert.strictEqual(res.data.default, null);
        });

        it('lists repos', function () {
            assert.ok(repos);
            assert(repos.length > 0);
        });

        it('ref "nonexistent" cannot be found in github sample repo ', function () {
            assert.deepStrictEqual(repos[0], {
                baseurl: 'https://api.github.com/',
                collection: 'tuttle-sample-data',
                deployed: '5006b2c',
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
});
