const util = require('./util.js')
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
        let res
        before(async function () {
            res = await util.axios.get('git/status', {auth: util.adminCredentials});
        });

        it('returns status 200', function () {
            expect(res.status).to.equal(200);
        });

        it('default repo', function () {
            expect(res.data.default).to.exist;
            expect(res.data.default).to.equal('tuttle-sample-data');
        });

        it('lists repos', function () {
            expect(res.data.repos).to.exist;
            expect(res.data.repos.repo).to.exist;
            expect(res.data.repos.repo.length).to.be.greaterThan(0);
        });

        it('github sample repo is up to date', function () {
            expect(res.data.repos.repo[0]).to.deep.equal({
                "type": "github",
                "url": "https://github.com/eeditiones/tuttle-sample-data",
                "ref": "main",
                "collection": "tuttle-sample-data",
                "message": "",
                "status": "uptodate"
            });
        });

        it('gitlab sample repo is not authorized', function () {
            expect(res.data.repos.repo[1]).to.deep.equal({
                "type": "gitlab",
                "url": "",
                "ref": "master",
                "collection": "tuttle-sample-gitlab",
                "message": "gitlab error: Unauthorized",
                "status": "error"
            });
        });
    });

    describe('git/lockfile', function () {
        let res
        before(async function () {
            res = await util.axios.get('git/lockfile', {auth: util.adminCredentials});
        });

        it('returns status 200', function () {
            expect(res.status).to.equal(200);
        });

        it('confirms no lockfile to be present', function () {
            expect(res.data.message).to.equal("lockfile not exist");
        });
    });
});
