import { axios, auth, getResourceInfo, ensureTuttleIsInstalled } from './util.js';
import { describe, it, before } from 'node:test';
import assert from 'node:assert';

export default () =>
    describe('Gitlab', async function () {
        before(async () => {
            await ensureTuttleIsInstalled();
        });
        const testHASH = '79789e5';
        const collection = 'tuttle-sample-gitlab';

        await it('Remove lockfile', async function () {
            const resultPromise = axios.post(`git/${collection}/lockfile`, {}, { auth });
            await assert.doesNotReject(resultPromise, 'The request should succeed');
            const res = await resultPromise;
            assert.strictEqual(res.status, 200);
        });

        await it('Get changelog', async function () {
            const resultPromise = axios.get(`git/${collection}/commits`, { auth });
            await assert.doesNotReject(resultPromise, 'The request should succeed');
            const res = await resultPromise;
            assert.strictEqual(res.status, 200);
            // console.log(res.data)
            assert(res.data.commits.length > 2);
        });

        await it('Pull ' + testHASH + ' into staging collection', async function () {
            const resultPromise = axios.get(`git/${collection}?hash=${testHASH}`, { auth });
            await assert.doesNotReject(resultPromise, 'The request should succeed');
            const res = await resultPromise;

            assert.strictEqual(res.status, 200);
            assert.deepStrictEqual(res.data, {
                message: 'success',
                collection: `/db/apps/${collection}-stage`,
                hash: testHASH,
            });
        });

        await it('Deploy staging to target collection', async function () {
            const resultPromise = axios.post(`git/${collection}`, {}, { auth });
            await assert.doesNotReject(resultPromise, 'The request should succeed');
            const res = await resultPromise;
            assert.strictEqual(res.status, 200);
            assert.strictEqual(res.data.message, 'success');
        });

        await it('Check Hashes', async function () {
            const resultPromise = axios.get(`git/${collection}/hash`, { auth });
            await assert.doesNotReject(resultPromise, 'the request should succeed');
            const res = await resultPromise;

            assert.strictEqual(res.status, 200);
            assert.strictEqual(res.data['local-hash'], testHASH);
        });

        await describe('Incremental update', async function () {
            let newFiles;
            let delFiles;

            await it('can do a dry run', async function () {
                const resultPromise = axios.post(
                    `git/${collection}/incremental?dry=true`,
                    {},
                    { auth },
                );
                await assert.doesNotReject(resultPromise, 'The request should succeed');
                const dryRunResponse = await resultPromise;

                await it('Succeeds', function () {
                    assert.strictEqual(dryRunResponse.status, 200);
                    assert.strictEqual(dryRunResponse.data.message, 'dry-run');
                });

                await it('Returns a list of new resources', async function () {
                    newFiles = await Promise.all(
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

                    assert.deepStrictEqual(newFiles[1], [{ path: 'data/F-tit2.xml' }, undefined]);

                    assert.strictEqual(newFiles[2][0].path, 'data/F-ham.xml');
                    assert(newFiles[2][1] instanceof Date);
                });

                await it('Returns a list of resources to be deleted', async function () {
                    delFiles = dryRunResponse.data.changes.del;

                    assert(delFiles.length > 0);
                    assert.deepStrictEqual(delFiles, [
                        { path: 'data/F-wiv.xml' },
                        { path: 'data/F-tit.xml' },
                    ]);
                });
            });

            await it('can do a run', async function () {
                let incrementalUpdateResponse;
                before(async function () {
                    incrementalUpdateResponse = await axios.post(
                        `git/${collection}/incremental`,
                        {},
                        { auth },
                    );
                    // console.log('incrementalUpdateResponse', incrementalUpdateResponse.data)
                });

                await it('succeeds', function () {
                    assert.strictEqual(incrementalUpdateResponse.status, 200);
                    assert.strictEqual(incrementalUpdateResponse.data.message, 'success');
                });

                await it('updates all changed resources', async function () {
                    await Promise.all(
                        newFiles.map(async (resource) => {
                            const { modified } = await getResourceInfo(
                                `/db/apps/${collection}/${resource[0].path}`,
                            );
                            assert.notStrictEqual(modified, undefined);
                            assert.notStrictEqual(modified, resource[1]);
                        }),
                    );
                });

                await it('deletes all deleted resources', async function () {
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
