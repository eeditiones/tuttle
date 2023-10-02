const { auth, axios, putResource } = require('./util.js')
const { readFile } = require('node:fs/promises')
const chai = require('chai')
const expect = chai.expect

describe('Tuttle', function () {
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
                baseurl: "https://api.github.com/",
                collection: "tuttle-sample-data",
                deployed: "5006b2c",
                hookuser: "admin",
                message: "remote found",
                owner: "eeditiones",
                path: "/db/apps/tuttle-sample-data",
                "project-id": null,
                ref: "next",
                remote: "5006b2c",
                repo: "tuttle-sample-data",
                status: "uptodate",
                url: "https://github.com/eeditiones/tuttle-sample-data",
                type: "github"
            });
        });

        it('gitlab sample repo is not authorized', function () {
            expect(repos[1]).to.deep.equal({
                baseurl: "https://gitlab.com/api/v4/",
                collection: "tuttle-sample-gitlab",
                deployed: "d80c71f",
                hookuser: "admin",
                message: "remote found",
                owner: "line-o",
                path: "/db/apps/tuttle-sample-gitlab",
                "project-id": "50872175",
                ref: "main",
                remote: "d80c71f",
                repo: "tuttle-sample-data",
                status: "uptodate",
                type: "gitlab",
                url: "https://gitlab.com/line-o/tuttle-sample-data.git",
                type: "gitlab"
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
        let res, repos

        before(async function () {
            const buffer = await readFile('./test/fixtures/alt-tuttle.xml')
            await putResource(buffer, '/db/apps/tuttle/data/tuttle.xml')
            res = await axios.get('git/status', { auth });
            repos = res.data.repos
        });

        it('returns status 200', function () {
            expect(res.status).to.equal(200);
        });

        it('has no default repo', function () {
            expect(res.data.default).not.to.exist;
        });

        it('lists repos', function () {
            expect(repos).to.exist;
            expect(repos.length).to.be.greaterThan(0);
        });

        it('ref "nonexistent" cannot be found in github sample repo ', function () {
            expect(repos[0]).to.deep.equal({
                baseurl: "https://api.github.com/",
                collection: "tuttle-sample-data",
                deployed: "5006b2c",
                hookuser: "admin",
                message: "server connection failed: Not Found (404)",
                owner: "eeditiones",
                path: "/db/apps/tuttle-sample-data",
                "project-id": null,
                ref: "nonexistent",
                repo: "tuttle-sample-data",
                status: "error",
                type: "github"
            });
        });
    });

});
