const util = require('./util.js')
const chai = require('chai')
const expect = chai.expect

describe('Tuttle', function () {
    let response

    before(async function () {
        await util.login()
        response = await util.axios.get('git/status', {})
    })
    console.log("DEBUG1: " + process.env.tuttle_token_tuttle_sample_data); 
    console.log("DEBUG2: " + process.env.TUTTLE_TOKEN_TUTTLE_SAMPLE_DATA); 
    it('Status', function () {
        expect(response.status).to.equal(200);
    })
    
})
