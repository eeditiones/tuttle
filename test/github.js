import { axios, auth, getResourceInfo, ensureTuttleIsInstalled } from './util.js';
import { before, describe, it } from 'node:test';
import assert from 'node:assert';

export default () =>
    describe('Github', async function () {
        before(async () => {
            await ensureTuttleIsInstalled();
        });
        const testHASH = '79789e5c4842afaaa63c733c3ed6babe37f70121';
        const collection = 'tuttle-sample-data';

        it('Remove lockfile', async function () {
            const resultPromise = axios.get('git/lockfile', { auth });
            await assert.doesNotReject(resultPromise, 'The request should succeed');
            const res = await resultPromise;
            assert.strictEqual(res.status, 200, res.statusText);
        });

        it('Get changelog', async function () {
            const resultPromise = axios.get('git/commits', { auth });
            await assert.doesNotReject(resultPromise, 'The request should succeed');
            const res = await resultPromise;

            assert.strictEqual(res.status, 200);
            assert(res.data.commits.length > 2, 'there should have been at least two commits');
        });

        it('Pull ' + testHASH + ' into staging collection', async function () {
            const resultPromise = axios.get(`git/?hash=${testHASH}`, { auth });
            await assert.doesNotReject(resultPromise, 'The request should succeed');
            const res = await resultPromise;

            assert.strictEqual(res.status, 200);
            assert.deepStrictEqual(res.data, {
                message: 'success',
                collection: `/db/apps/${collection}-stage`,
                hash: testHASH,
            });
        });

        it('Deploy staging to target collection', async function () {
            const resultPromise = axios.post('git/', {}, { auth });
            await assert.doesNotReject(resultPromise, 'The request should succeed');
            const res = await resultPromise;
            assert.strictEqual(res.status, 200);
            assert.strictEqual(res.data.message, 'success');
        });

        it('Check Hashes', async function () {
            const resultPromise = axios.get('git/hash', { auth });
            await assert.doesNotReject(resultPromise, 'The request should succeed');
            const res = await resultPromise;

            assert.strictEqual(res.status, 200);
            assert.strictEqual(res.data['local-hash'], testHASH);
        });

        describe('Incremental update', async function () {
            describe('can do a dry run', async function () {
                let resultPromise, dryRunResponse

                before(async function () {
                    resultPromise = axios.post('git/incremental?dry=true', {}, { auth });
                    await assert.doesNotReject(resultPromise, 'The request should succeed');
                    dryRunResponse = await resultPromise;
                })

                it('Succeeds', function () {
                    assert.strictEqual(dryRunResponse.status, 200);
                    assert.strictEqual(dryRunResponse.data.message, 'dry-run');
                });

                it('Returns a list of new resources', async function () {
                    const newFiles = await Promise.all(
                        dryRunResponse.data.changes.new.map(async (resource) => {
                            const resourceInfo = await getResourceInfo(
                                `/db/apps/${collection}/${resource.path}`,
                            );
                            return [resource, resourceInfo.modified];
                        }),
                    );
                    // console.log('files to fetch', newFiles)

                    assert.strictEqual(newFiles.length, 3);
                    assert.strictEqual(newFiles[0][0].path, 'data/F-aww.xml');
                    assert(newFiles[0][1] instanceof Date);

                    assert.deepStrictEqual(
                        newFiles[1],
                        [{ path: 'data/F-tit2.xml' }, undefined],
                        'File was added, so no modified timestamp is expected',
                    );

                    assert.strictEqual(newFiles[2][0].path, 'data/F-ham.xml');
                    assert(newFiles[2][1] instanceof Date);
                });

                it('Returns a list of resources to be deleted', async function () {
                    const delFiles = dryRunResponse.data.changes.del;

                    assert(delFiles.length > 0);
                    assert.deepStrictEqual(delFiles, [
                        { path: 'data/F-wiv.xml' },
                        { path: 'data/F-tit.xml' },
                    ]);
                });
            });

            describe('can do a run', async function () {
                let resultPromise, incrementalUpdateResponse

                before(async function () {
                    const resultPromise = axios.post('git/incremental', {}, { auth });
                    await assert.doesNotReject(resultPromise, 'The request should succeed');
                    incrementalUpdateResponse = await resultPromise;
                })

                it('succeeds', function () {
                    assert.strictEqual(incrementalUpdateResponse.status, 200);
                    assert.strictEqual(incrementalUpdateResponse.data.message, 'success');
                });

                it('updates all changed resources', async function () {
                    const newFiles = await Promise.all(
                        incrementalUpdateResponse.data.changes.new.map(async (resource) => {
                            const resourceInfo = await getResourceInfo(
                                `/db/apps/${collection}/${resource.path}`,
                            );
                            return [resource, resourceInfo.modified];
                        }),
                    );

                    await Promise.all(
                        newFiles.map(async (resource) => {
                            const { modified } = await getResourceInfo(
                                `/db/apps/${collection}/${resource[0].path}`,
                            );
                            assert.ok(modified);
                            assert.notStrictEqual(modified, resource[1]);
                        }),
                    );
                });

                it('deletes all deleted resources', async function () {
                    const delFiles = incrementalUpdateResponse.data.changes.del;

                    await Promise.all(
                        delFiles.map(async (resource) => {
                            const resourceInfo = await getResourceInfo(
                                `/db/apps/${collection}/${resource.path}`,
                            );
                            assert.deepStrictEqual(resourceInfo, {});
                        }),
                    );
                });
            });
        });
    });
