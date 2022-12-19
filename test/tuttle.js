const util = require('./util.js')
const chai = require('chai')
const expect = chai.expect

describe('Tuttle', function () {
    let response

    before(async function () {
        await util.login()
        response = await util.axios.get('git/status', {})
    })

    it('Status', function () {
        expect(response.status).to.equal(200);
    })
    
})
