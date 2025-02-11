/**
 * an example gulpfile to make ant-less existdb package builds a reality
 */
import { src, dest, watch, series, parallel, lastRun } from 'gulp'
import { createClient } from '@existdb/gulp-exist'
import replace from '@existdb/gulp-replace-tmpl'
import zip from 'gulp-zip'
import rename from 'gulp-rename'
import del from 'delete'

import pkg from './package.json' with { type: 'json' }
const { app, version, license } = pkg
const replacements = [app, { version, license }]

const packageUri = app.namespace

// read metadata from .existdb.json
import existJSON from './.existdb.json' with { type: 'json' }
const serverInfo = existJSON.servers.localhost
const url = new URL(serverInfo.server)
const connectionOptions = {
    host: url.hostname,
    port: url.port,
    secure: url.protocol === 'https:',
    basic_auth: {
        user: serverInfo.user,
        pass: serverInfo.password
    }
}
const existClient = createClient(connectionOptions);

/**
 * Use the `delete` module directly, instead of using gulp-rimraf
 */
function clean (cb) {
    del(['build', 'dist'], cb);
}

/**
 * replace placeholders
 * in src/repo.xml.tmpl and
 * output to build/repo.xml
 */
function templates () {
    return src('src/*.tmpl')
        .pipe(replace(replacements, {unprefixed:true}))
        .pipe(rename(path => { path.extname = "" }))
        .pipe(dest('build/'))
}

function watchTemplates () {
    watch('src/*.tmpl', series(templates))
}


const staticFiles = 'src/**/*.{xml,html,xq,xqm,xsl,xconf,json,svg,js,css,png,jpg,map}'

/**
 * copy html templates, XSL stylesheet, XMLs and XQueries to 'build'
 */
function copyStatic () {
    return src(staticFiles).pipe(dest('build'))
}

function watchStatic () {
    watch(staticFiles, series(copyStatic));
}

/**
 * Upload all files in the build folder to existdb.
 * This function will only upload what was changed
 * since the last run (see gulp documentation for lastRun).
 */
function deployApp () {
    return src('build/**/*', {
        base: 'build/',
        since: lastRun(deploy)
    })
        .pipe(existClient.dest({target}))
}

function watchBuild () {
    watch('build/**/*', series(deploy))
}

// construct the current xar name from available data
const xarFilename = `${app.abbrev}-${version}.xar`

/**
 * create XAR package in repo root
 */
function createXar () {
    return src('build/**/*', {base: 'build/'})
        .pipe(zip(xarFilename))
        .pipe(dest('dist'))
}

/**
 * upload and install the latest built XAR
 */
function installXar () {
    return src(xarFilename, { cwd:'dist/', encoding: false })
        .pipe(existClient.install({ packageUri }))
}


// composed tasks
const build = series(
    clean,
    templates,
    copyStatic
)
const deploy = series(build, deployApp)
const watchAll = parallel(
    watchStatic,
    watchTemplates,
    watchBuild
)

const xar = series(build, createXar)
const install = series(build, xar, installXar)

export {
 clean,
 templates,
 watchTemplates,
 copyStatic,
 watchStatic,
 build,
 deploy,
 xar,
 install,
 watchAll as watch,
}

// main task for day to day development
export default series(build, deploy, watchAll)