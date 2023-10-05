const { axios, auth, getResourceInfo } = require('./util.js')
const chai = require('chai')
const expect = chai.expect

describe('Github', function () {
  this.timeout(15000);
  
  const testHASH = '79789e5';
  const collection = 'tuttle-sample-data'

  it('Remove lockfile', async function () {
    const res = await axios.post('git/lockfile', {}, { auth });
    expect(res.status).to.equal(200);
  });

  it('Get changelog', async function () {
    const res = await axios.get('git/commits', { auth });
    expect(res.status).to.equal(200);
    expect(res.data.commits.length).to.be.greaterThan(2);
  });

  it('Pull ' + testHASH + ' into staging collection', async function () {
    const res = await axios.get(`git/?hash=${testHASH}`, { auth });

    expect(res.status).to.equal(200);
    expect(res.data).to.deep.equal({
      message: 'success',
      collection: `/db/apps/${collection}-stage`,
      hash: testHASH
    });
});

  it('Deploy staging to target collection', async function () {
    const res = await axios.post('git/', {}, { auth });
    expect(res.status).to.equal(200);
    expect(res.data).to.deep.include({ message: 'success'});
  });

  it('Check Hashes', async function () {
    const res = await axios.get('git/hash', { auth });

    expect(res.status).to.equal(200);
    expect(res.data).to.deep.include({ 'local-hash': testHASH });
  });

  describe('Incremental update', function () {
    let newFiles;
    let delFiles;

    describe('dry run', function () {
      let dryRunResponse

      before(async function () {
        this.timeout(10000);
        dryRunResponse = await axios.post('git/incremental?dry=true', {}, { auth });

        // console.log('message', dryRunResponse.data.message)
      })

      it('Succeeds', function () {
        expect(dryRunResponse.status).to.equal(200);
        expect(dryRunResponse.data.message).to.equal('dry-run');
      })

      it('Returns a list of new resources', async function () {
        newFiles = await Promise.all(dryRunResponse.data.changes.new.map(async (resource) => {
          const resourceInfo = await getResourceInfo(`/db/apps/${collection}/${resource}`);
          return [resource, resourceInfo.modified];
        }))
        // console.log('files to fetch', newFiles)

        expect(newFiles.length).to.equal(3);
        expect(newFiles[0][0]).to.equal('data/F-aww.xml')
        expect(newFiles[0][1]).to.be.a('date')

        expect(newFiles[1]).to.deep.equal([ 'data/F-tit2.xml', undefined ])

        expect(newFiles[2][0]).to.equal('data/F-ham.xml')
        expect(newFiles[2][1]).to.be.a('date')
      });
  
      it('Returns a list of resources to be deleted', async function () {
        delFiles = dryRunResponse.data.changes.del;

        expect(delFiles.length).to.be.greaterThan(0);
        expect(delFiles).to.deep.equal(
          [ 'data/F-wiv.xml', 'data/F-tit.xml' ]
        );
      });
    })

    describe('run', function () {
      let incrementalUpdateResponse
      before(async function () {
        this.timeout(10000);
        incrementalUpdateResponse = await axios.post('git/incremental', {}, { auth });
        // console.log('incrementalUpdateResponse', incrementalUpdateResponse.data.changes)
      })

      it('succeeds', function () {
        expect(incrementalUpdateResponse.status).to.equal(200);
        expect(incrementalUpdateResponse.data.message).to.equal('success');
      });

      it('updates all changed resources', async function () {
        await Promise.all(newFiles.map(async (resource) => {
          const { modified } = await getResourceInfo(`/db/apps/${collection}/${resource[0]}`);
          expect(modified).to.not.be.undefined;
          expect(modified).to.not.equal(resource[1]);
        }))
      })

      it('deletes all deleted resources', async function () {
        await Promise.all(delFiles.map(async (resource) => {
          const resourceInfo = await getResourceInfo(`/db/apps/${collection}/${resource}`);
          expect(resourceInfo).is.empty;
        }))
      })
    })
  })
})

