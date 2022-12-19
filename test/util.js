const chai = require('chai');
const expect = chai.expect;
const axios = require('axios');
const https = require('https')
const {connect} = require('@existdb/node-exist')

// read connction options from ENV
const params = { user: 'admin', password: '' }
if (process.env.EXISTDB_USER && 'EXISTDB_PASS' in process.env) {
    params.user = process.env.EXISTDB_USER
    params.password = process.env.EXISTDB_PASS
}

// for use in custom controller tests
const adminCredentials = {
    username: params.user,
    password: params.password
}

const server = 'EXISTDB_SERVER' in process.env
    ? process.env.EXISTDB_SERVER
    : 'https://localhost:8443'
  
const {origin, hostname} = new URL(server)

const axiosInstance = axios.create({
    baseURL: `${origin}/exist/apps/tuttle`,
    headers: { Origin: origin },
    withCredentials: true,
    httpsAgent: new https.Agent({
        rejectUnauthorized: hostname !== 'localhost'
    })
});

const db = connect({
    basic_auth: {
        user: adminCredentials.username,
        pass: adminCredentials.password
    }
})

// getResourceInfo("/db/apps/tuttle-sample-data/data/F-1h4.xml")
async function getResourceInfo(resource){
    resInfo =  await db.resources.describe(resource)
    return resInfo;
}

async function login() {
    // console.log('Logging in ' + serverInfo.user + ' to ' + app)
    const res = await axiosInstance.request({
        url: 'login',
        method: 'post',
        params
    });

    const cookie = res.headers['set-cookie'];
    axiosInstance.defaults.headers.Cookie = cookie[0];
    // console.log('Logged in as %s: %s', res.data.user, res.statusText);
}

async function logout(done) {
    const res = await axiosInstance.request({
        url: 'logout',
        method: 'get'
    })

    const cookie = res.headers["set-cookie"]
    axiosInstance.defaults.headers.Cookie = cookie[0]
    // console.log('Logged in as %s: %s', res.data.user, res.statusText)
}

module.exports = {axios: axiosInstance, login, logout, adminCredentials, getResourceInfo};
//getResourceInfo("/db/apps/tuttle-sample-data/data/F-ham.xml");