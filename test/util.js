const axios = require('axios');
const https = require('https')
const { connect } = require('@existdb/node-exist')
const { user, password, server } = require('../.existdb.json').servers.localhost

// for use in custom controller tests
const adminCredentials = { username: user, password }

// read connction options from ENV
if (process.env.EXISTDB_USER && 'EXISTDB_PASS' in process.env) {
    adminCredentials.username = process.env.EXISTDB_USER
    adminCredentials.password = process.env.EXISTDB_PASS
}

const testServer = 'EXISTDB_SERVER' in process.env
    ? process.env.EXISTDB_SERVER
    : server

const { origin, hostname, port, protocol } = new URL(testServer)

const axiosInstanceOptions = {
    baseURL: `${origin}/exist/apps/tuttle`,
    headers: { Origin: origin },
    withCredentials: true
}

const rejectUnauthorized = !(
    hostname === 'localhost' ||
    hostname === '127.0.0.1'
)
const secure = protocol === 'https:'

if (secure) {
    axiosInstanceOptions.httpsAgent = new https.Agent({ rejectUnauthorized })
}

const axiosInstance = axios.create(axiosInstanceOptions);

const db = connect({
    host: hostname,
    port,
    secure,
    rejectUnauthorized,
    basic_auth: {
        user: adminCredentials.username,
        pass: adminCredentials.password
    }
})

async function putResource (buffer, path) {
    const fh = await db.documents.upload(buffer)
    return await db.documents.parseLocal(fh, path, {})
}

function getResourceInfo (resource) {
    return db.resources.describe(resource)
}

module.exports = {
    axios: axiosInstance, 
    auth: adminCredentials,
    getResourceInfo,
    putResource
};
//getResourceInfo("/db/apps/tuttle-sample-data/data/F-ham.xml");