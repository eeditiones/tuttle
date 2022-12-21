const util = require('./util.js')
const chai = require('chai')
const expect = chai.expect

describe('Tuttle', function () {

    it('Status', async function () {
        const res = await util.axios.get('git/status', {auth: util.adminCredentials});
    
        expect(res.status).to.equal(200);
    });

    it('Print Lockfile', async function () {
        const res = await util.axios.get('git/lockfile', {auth: util.adminCredentials});
    
        expect(res.status).to.equal(200);
    });


})
