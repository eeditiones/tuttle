const axios = require('axios');
const https = require('https')
const { connect } = require('@existdb/node-exist')
const { user, password, server } = require('../.existdb.json').servers.localhost
const appNamespace = require('../package.json').app.namespace
const { readFile } = require('node:fs/promises')
const path = require('path');
const { readdir } = require('fs/promises');

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

async function install () {
    const matches = (await readdir('dist')).filter(entry => entry.endsWith('.xar'))

    if (matches.length > 1) {
        throw new Error(`Multiple tuttle versions: ${matches}`)
    }
    if (matches.length === 0) {
        throw new Error(`No tuttle.xar found. Run 'npm build' before running tests`)
    }

    const xarFile = path.join('dist', matches[0])
    const xarContents = await readFile(xarFile)
    const xarName = path.basename(xarFile)
    await db.app.upload(xarContents, xarName)
    await db.app.install(xarName)
}

async function remove() {
	await db.app.remove(appNamespace)

	const result = await Promise.allSettled([
		db.collections.remove('/db/tuttle-backup'),
		db.collections.remove('/db/pkgtmp'),

		db.collections.remove('/db/apps/tuttle-sample-data'),
		db.collections.remove('/db/apps/tuttle-sample-gitlab'),
	])

	if (result.some(r => r.status === 'rejected')) {
		console.warn('clean up failed', result.filter(r => r.status === 'rejected').map(r => r.reason))
	}
}

module.exports = {
    axios: axiosInstance,
    auth: adminCredentials,
    getResourceInfo,
    putResource,
    install,
    remove,
};
//getResourceInfo("/db/apps/tuttle-sample-data/data/F-ham.xml");
