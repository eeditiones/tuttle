import { Agent } from 'node:https';
import { readFile, readdir } from 'node:fs/promises';
import { join, basename } from 'node:path';

import axios from 'axios';
import { connect } from '@existdb/node-exist';

import existJson from '../.existdb.json' with { type: 'json' };
const { user, password, server } = existJson.servers.localhost;

import pkg from '../package.json' with { type: 'json' };
const { namespace } = pkg.app;

// for use in custom controller tests
const adminCredentials = { username: user, password };

// read connction options from ENV
if (process.env.EXISTDB_USER && 'EXISTDB_PASS' in process.env) {
    adminCredentials.username = process.env.EXISTDB_USER;
    adminCredentials.password = process.env.EXISTDB_PASS;
}

const testServer = 'EXISTDB_SERVER' in process.env ? process.env.EXISTDB_SERVER : server;

const { origin, hostname, port, protocol } = new URL(testServer);

const axiosInstanceOptions = {
    baseURL: `${origin}/exist/apps/tuttle`,
    headers: { Origin: origin },
    withCredentials: true,
};

const rejectUnauthorized = !(hostname === 'localhost' || hostname === '127.0.0.1');
const secure = protocol === 'https:';

if (secure) {
    axiosInstanceOptions.httpsAgent = new Agent({ rejectUnauthorized });
}

const axiosInstance = axios.create(axiosInstanceOptions);

const db = connect({
    host: hostname,
    port,
    secure,
    rejectUnauthorized,
    basic_auth: {
        user: adminCredentials.username,
        pass: adminCredentials.password,
    },
});

async function putResource(buffer, path) {
    const fh = await db.documents.upload(buffer);
    return await db.documents.parseLocal(fh, path, {});
}

function getResourceInfo(resource) {
    return db.resources.describe(resource);
}

async function install() {
    const matches = (await readdir('dist')).filter((entry) => entry.endsWith('.xar'));

    if (matches.length > 1) {
        throw new Error(`Multiple tuttle versions: ${matches}`);
    }
    if (matches.length === 0) {
        throw new Error(`No tuttle.xar found. Run 'npm build' before running tests`);
    }

    const xarFile = join('dist', matches[0]);
    const xarContents = await readFile(xarFile);
    const xarName = basename(xarFile);
    console.log('Uploading tuttle');
    await db.app.upload(xarContents, xarName);
    console.log('Uploaded tuttle, installing');
    await db.app.install(xarName);
}

async function remove() {
    await db.app.remove(namespace);

    const result = await Promise.allSettled([
        db.collections.remove('/db/tuttle-backup'),
        db.collections.remove('/db/pkgtmp'),

        db.collections.remove('/db/apps/tuttle-sample-data'),
        db.collections.remove('/db/apps/tuttle-sample-gitlab'),
    ]);

    if (result.some((r) => r.status === 'rejected')) {
        console.warn(
            'clean up failed',
            result.filter((r) => r.status === 'rejected').map((r) => r.reason),
        );
    }
}

/**
 * @type {Promise void>}
 */
let tuttleInstallationPromise = null;

export async function ensureTuttleIsInstalled() {
    if (!tuttleInstallationPromise) {
        console.log('installing tuttle');
        tuttleInstallationPromise = remove().then(() => install());
    }
    await tuttleInstallationPromise;
    console.log('done installing tuttle');
}

export { axiosInstance as axios, adminCredentials as auth, getResourceInfo, putResource, install };
