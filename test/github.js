const util = require('./util.js')
const chai = require('chai')
const expect = chai.expect

describe('Github', function () {
  this.timeout(10000);
  
  let testHASH;
  
  it('Get changelog', async function () {
    const res = await util.axios.get('git/commits' + testHASH, {auth: util.adminCredentials});
    testHASH = res.data[2][0];

    expect(res.status).to.equal(200);
  });

  it('Pull three versions behind upstream into staging collection', async function () {
    const res = await util.axios.get('git/?hash=' + testHASH, {auth: util.adminCredentials});

    expect(res.status).to.equal(200);
    expect(res.data).to.deep.equal({'message': 'success'});
  });

  it('Deploy staging to target collection', async function () {
    const res = await util.axios.post('git/', {}, {auth: util.adminCredentials});

    expect(res.status).to.equal(200);
    expect(res.data).to.deep.include({'message': 'success'});
  });

  it('Check Hashes', async function () {
    const res = await util.axios.get('git/hash', {auth: util.adminCredentials});

    expect(res.status).to.equal(200);
    expect(res.data).to.deep.include({'local-hash': testHASH});
  });

  describe('Github incremental update', function () {
    this.timeout(10000);

    let newFiles = new Array();
    let delFiles = new Array();

    it('Get list of changed resources', async function () {
      const res = await util.axios.post('git/incremental?dry=true', {}, {auth: util.adminCredentials});
      delFiles = res.data.changes.del;

      if (typeof res.data.changes.new === 'string') {
        const resourceInfo = await util.getResourceInfo("/db/apps/tuttle-sample-data/" + res.data.changes.new);
        newFiles.push([res.data.changes.new, resourceInfo.modified]);
      } else {
        await Promise.all(res.data.changes.new.map(async (resource) => {
          const resourceInfo = await util.getResourceInfo("/db/apps/tuttle-sample-data/" + resource);
          newFiles.push([resource, resourceInfo.modified]);
        }));
      };

      expect(res.status).to.equal(200);
      expect(res.data).to.deep.include({'message': 'success'});
    });

    it('Run incremental update', async function () {
      this.timeout(10000);

      const res = await util.axios.post('git/incremental', {}, {auth: util.adminCredentials});

      expect(res.status).to.equal(200);
      expect(res.data).to.deep.include({'message': 'success'});
    });

    it('Check updated resources', async function () {
    await Promise.all(newFiles.map(async (resource) => {
      const resourceInfo = await util.getResourceInfo("/db/apps/tuttle-sample-data/" + resource[0]);
      expect(resourceInfo.modified).to.not.equal(resource[1]);
    }));

    if (typeof delFiles === 'string') {
      const resourceInfo = await util.getResourceInfo("/db/apps/tuttle-sample-data/" + delFiles);
      expect(resourceInfo).is.empty;
    } else {
      await Promise.all(delFiles.map(async (resource) => {
        const resourceInfo = await util.getResourceInfo("/db/apps/tuttle-sample-data/" + resource);
        expect(resourceInfo).is.empty;
      }));
    };
    }); 

  })
})

