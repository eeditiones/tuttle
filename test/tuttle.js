const { auth, axios, putResource } = require('./util.js')
const { readFile } = require('node:fs/promises')
const chai = require('chai')
const expect = chai.expect

describe('Tuttle', function () {
    // {
    //     "default": "tuttle-sample-data",
    //     "repos": {
    //       "repo": [
    //         {
    //           "type": "github",
    //           "url": "https://github.com/eeditiones/tuttle-sample-data",
    //           "ref": "main",
    //           "collection": "tuttle-sample-data",
    //           "message": "",
    //           "status": "uptodate"
    //         },
    //         {
    //           "type": "gitlab",
    //           "url": "",
    //           "ref": "master",
    //           "collection": "tuttle-sample-gitlab",
    //           "message": "gitlab error: Unauthorized",
    //           "status": "error"
    //         }
    //       ]
    //     }
    // }
    describe('git/status', function () {
        let res, repos, defaultRepo

        before(async function () {
            res = await axios.get('git/status', { auth });
            repos = res.data.repos
            defaultRepo = res.data.default

        });

        it('returns status 200', function () {
            expect(res.status).to.equal(200);
        });

        it('default repo', function () {
            expect(defaultRepo).to.exist;
            expect(defaultRepo).to.equal('tuttle-sample-data');
        });

        it('lists repos', function () {
            expect(repos).to.exist;
            expect(repos.length).to.be.greaterThan(0);
        });

        it('github sample repo is up to date', function () {
            expect(repos[0]).to.deep.equal({
                type: "github",
                url: "https://github.com/eeditiones/tuttle-sample-data",
                ref: "next",
                collection: "tuttle-sample-data",
                message: "remote found",
                deployed: "5006b2c",
                remote: "5006b2c",
                status: "uptodate"
            });
        });

        it('gitlab sample repo is not authorized', function () {
            expect(repos[1]).to.deep.equal({
                type: "gitlab",
                ref: "master",
                collection: "tuttle-sample-gitlab",
                message: "server connection failed: Unauthorized (401)",
                status: "error",
                deployed: null
            });
        });
    });

    describe('git/lockfile', function () {
        let res
        before(async function () {
            res = await axios.get('git/lockfile', { auth });
        });

        it('returns status 200', function () {
            expect(res.status).to.equal(200);
        });

        it('confirms no lockfile to be present', function () {
            expect(res.data.message).to.equal("No lockfile for 'tuttle-sample-data' found.");
        });
    });

    describe('git/status with different settings', function () {
        let res, repos, defaultRepo

        before(async function () {
            const buffer = await readFile('./test/fixtures/alt-tuttle.xml')
            await putResource(buffer, '/db/apps/tuttle/data/tuttle.xml')
            res = await axios.get('git/status', { auth });
            repos = res.data.repos
            defaultRepo = res.data.default
        });

        it('returns status 200', function () {
            expect(res.status).to.equal(200);
        });

        it('has a default repo', function () {
            expect(defaultRepo).to.exist;
            expect(defaultRepo).to.equal('tuttle-sample-data');
        });

        it('lists repos', function () {
            expect(repos).to.exist;
            expect(repos.length).to.be.greaterThan(0);
        });

        it('ref "next" cannot be found in github sample repo ', function () {
            expect(repos[0]).to.deep.equal({
                type: 'github',
                deployed: '5006b2c',
                ref: 'nonexistent',
                collection: "tuttle-sample-data",
                message: "server connection failed: Not Found (404)",
                status: "error"
            });
        });
    });

});
