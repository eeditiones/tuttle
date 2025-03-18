import { axios, auth, getResourceInfo, ensureTuttleIsInstalled } from './util.js';
import { before, describe, it } from 'node:test';
import assert from 'node:assert';

describe('Github', function () {
    before(async () => {
        await ensureTuttleIsInstalled();
    });
    const testHASH = '79789e5';
    const collection = 'tuttle-sample-data';

    it('Remove lockfile', async function () {
        try {
            const res = await axios.post('git/lockfile', {}, { auth });
            assert.strictEqual(res.status, 200, res.statusText);
        } catch (err) {
            console.log(err.toJSON());
        }
    });

    it('Get changelog', async function () {
        let res;
        res = await axios.get('git/commits', { auth });
        assert.strictEqual(res.status, 200);
        assert(res.data.commits.length > 2, 'there should have been at least two commits');
    });

    it('Pull ' + testHASH + ' into staging collection', async function () {
        const res = await axios.get(`git/?hash=${testHASH}`, { auth });

        assert.strictEqual(res.status, 200);
        assert.deepStrictEqual(res.data, {
            message: 'success',
            collection: `/db/apps/${collection}-stage`,
            hash: testHASH,
        });
    });

    it('Deploy staging to target collection', async function () {
        const res = await axios.post('git/', {}, { auth });
        assert.strictEqual(res.status, 200);
        assert.strictEqual(res.data.message, 'success');
    });

    it('Check Hashes', async function () {
        const res = await axios.get('git/hash', { auth });

        assert.strictEqual(res.status, 200);
        assert.strictEqual(res.data['local-hash'], testHASH);
    });

    describe('Incremental update', function () {
        let newFiles;
        let delFiles;

        describe('dry run', function () {
            let dryRunResponse;

            before(async function () {
                dryRunResponse = await axios.post('git/incremental?dry=true', {}, { auth });

                // console.log('message', dryRunResponse.data.message)
            });

            it('Succeeds', function () {
                assert.strictEqual(dryRunResponse.status, 200);
                assert.strictEqual(dryRunResponse.data.message, 'dry-run');
            });

            it('Returns a list of new resources', async function () {
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

                assert.deepStrictEqual(
                    newFiles[1],
                    [{ path: 'data/F-tit2.xml' }, undefined],
                    'File was added, so no modified timestamp is expected',
                );

                assert.strictEqual(newFiles[2][0].path, 'data/F-ham.xml');
                assert(newFiles[2][1] instanceof Date);
            });

            it('Returns a list of resources to be deleted', async function () {
                delFiles = dryRunResponse.data.changes.del;

                assert(delFiles.length > 0);
                assert.deepStrictEqual(delFiles, [
                    { path: 'data/F-wiv.xml' },
                    { path: 'data/F-tit.xml' },
                ]);
            });
        });

        describe.skip('run', function () {
            let incrementalUpdateResponse;
            before(async function () {
                incrementalUpdateResponse = await axios.post('git/incremental', {}, { auth });
                // console.log('incrementalUpdateResponse', incrementalUpdateResponse.data.changes)
            });

            it('succeeds', function () {
                assert.strictEqual(incrementalUpdateResponse.status, 200);
                assert.strictEqual(incrementalUpdateResponse.data.message, 'success');
            });

            it('updates all changed resources', async function () {
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
