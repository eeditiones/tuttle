 
# Tuttle - a Git-integration for eXist-db

Synchronizes your data collection with GitHub and GitLab.

## User Documentation

[User Documentation](https://eeditiones.github.io/tuttle-doc/)

## Functionality

* Sync data collection from Git to DB
* Deal with multiple repositories
* Incremental updates
* Works with private or public repositories

## Requirements

-  [node](https://nodejs.org/en/): `v18`
-  [gulp](https://gulpjs.com): `v4.x` (for building)
-  [exist-db](https://www.exist-db.org): `v5.5.1+ < 7.0.0`

## Building and Installation

Tuttle uses Gulp as its build tool which itself builds on NPM. 
To initialize the project and load dependencies run

```npm i```

> Note: the `install` commands below assume that you have a local eXist-db running on port 8080. However the database connection can be modified in `.existdb.json.`

| Run | Description |
|---------|-------------|
|```npm run build```|to just build Tuttle. |
|```npm run deploy```|To build and install Tuttle in one go|

The resulting xar(s) are found in the root of the project.

## Testing

To run the local test suite you need an
* instance of eXist running on `localhost:8080` and 
* `npm` to be available in your path
* a GitHub personal access token with read access to public repositories
* a gitlab personal access token with read access to public repositories

In CI these access tokens are read from environment variables.
You can do the same with
```bash
export tuttle_token_tuttle_sample_data=<GITHUB_PAT>; \ 
export tuttle_token_gitlab_sample_data=<GITLAB_PAT>; \ 
path/to/startup.sh
```

Alternatively, you can modify `/db/apps/tuttle/data/tuttle.xml` _and_ `test/fixtures/alt-tuttle.xml` to include your tokens. But remember to never commit them!

Run tests with ```npm test```

## Configuration

Tuttle is configured in `data/tuttle.xml`. 

New with version 2.0.0:

A commented example configuration is available `data/tuttle-example-config.xml`.
If you want to update tuttle your modified configuration file will be backed up to
`/db/tuttle-backup/tuttle.xml` and restored on installation of the new version.

Otherwise, when no back up of an existing config-file is found, the example configuration is copied to `data/tuttle.xml`.

> [!TIP]
> When migrating from an earlier version you can copy your existing configuration to the backup location:
> `xmldb:copy-resource('/db/apps/tuttle/data', 'tuttle.xml', '/db/tuttle-backup', 'tuttle.xml')`

### Repository configuration 

The repositories to keep in sync with a gitservice are all listed under the repos-element.

The name-attribute refers to the **destination collection** also known as the **target collection**.

#### Collection

An example: `<collection name="tuttle-sample-data">`
The collection `/db/apps/tuttle-sample-data` is now considered to be kept in sync with a git repository.

```xml
<collection name="tuttle-sample-data">
    <default>true</default>

    <type>github</type>
    <baseurl>https://api.github.com/</baseurl>

    <repo>tuttle-sample-data</repo>
    <owner>tuttle-sample-data</owner>

    <token>a-personal-access-token</token>

    <ref>a-branch</ref>

    <hookuser>a-exist-user</hookuser>
    <hookpasswd>that-users-password</hookpasswd>
</collection>
```

#### type

```xml
<type>gitlab</type>
```

There are two supported git services at the moment `github` and `gitlab`

#### baseurl

```xml
<baseurl>https://api.server/</baseurl>
```

* For github the baseurl is `https://api.github.com/` or your github-enterprise API endpoint
* For gitlab the baseurl is `https://gitlab.com/api/v4/` but can also be your private gitlab server egg 'https://gitlab.existsolutions.com/api/v4/'

#### repo, owner and project-id

* For github you **have to** specify the owner and the repo
* For gitlab you **have to** specify the project-id of the repository


#### ref

```xml
<ref>main</ref>
```

Defines the branch you want to track. 

#### hookuser & hookpasswd

#### token

If a token is specified Tuttle authenticates against GitHub or GitLab. When a token is not defined, Tuttle assumes a public repository without any authentication.

> [!NOTE]
> Be aware of the rate limits for unauthenticated requests
> GitHub allows 60 unauthenticated requests per hour but 5,000 for authenticated requests

> [!TIP]
> It is also possible to pass the token via an environment variable. The name of the variable have to be  `tuttle_token_ + collection` (all dashes must be replaces by underscore). Example: `tuttle_token_tuttle_sample_data`

##### Create API-Keys for Github / Gitlab

At this stage of development, the API keys must be generated via the API endpoint `/git/apikey` or for a specific collection `/git/{collection}/apikey`. 

In the configuration `tuttle.xml` the "hookuser" is used to define the dbuser which executes the update.

Example configuration for GitHub:
 * 'Payload URL': https://existdb:8443/exist/apps/tuttle/git/hook
 * 'Content type': application/json

Example configuration for GitLab:
 * 'URL' : https://46.23.86.66:8443/exist/apps/tuttle/git/hook


## Dashboard

The dashboard can trigger a full deployment or an incremental update. 
Full deployment clones the repository from git and install it as a `.xar` file.
With incremental update only the changes to the database collection are applied.

> [!NOTE]
> Tuttle is built to keep track of **data collections**

> [!NOTE]
> Tuttle is does not run pre- or post install scripts nor change the index configuration on incremental updates!

### Lets start

1) customize the configuration (`data/tuttle.xml`)
2) click on 'full' to trigger a full deployment from git to existdb
3) now you can update your collection with a click on 'incremental'

Repositories from which a valid XAR (existing `expath-pkg.xml` and `repo.xml`) package can be generated are installed as a package, all others are created purely on the DB.

> [!NOTE]
> Note that there may be index problems if a collection is not installed as a package.

## API

The page below is reachable via [api.html](api.html) in your installed tuttle app. 

![Tuttle](doc/Tuttle-OpenAPI.png)

### API endpoint description

Calling the API without {collection} ``config:default-collection()`` is chosen. 

#### Fetch to staging collection

`` GET ~/tuttle/{collection}/git``

With this most basic endpoint the complete data repository is pulled from the gitservice.
The data will not directly update the target collection but be stored in a staging
collection. 

To update the target collection use another POST request to `/tuttle/git`.

The data collection is stored in `/db/app/sample-collection-staging`.

#### Deploy the collection

`` POST ~/tuttle/{collection}/git``

The staging collection `/db/app/sample-collection-staging` is deployed to `/db/app/sample-collection`. All permissions are set and a pre-install function is called if needed.

#### Incremental update

`` POST ~/tuttle/{collection}/git``

All commits since the last update are applied.To ensure the integrity of the collection, all commits are deployed individually.

#### Get the repository hashed

`` GET ~/tuttle/{collection}/hash``

Reports the GIT hashed of all participating collections and the hash of the remote repository.

#### Get Commits

`` GET ~/tuttle/{collection}/commits``

Displays all commits with commit message of the repository. 

#### Hook Trigger

`` GET ~/tuttle/{collection}/hook``

The webhook is usually triggered by GitHub or GitLab.
An incremental update is triggered.
Authentication is done by APIKey. The APIKey must be set in the header of the request.

#### Example für GitLab
``` curl --header 'X-Gitlab-Token: RajWFNCILBuQ8SWRfAAAJr7pHxo7WIF8Fe70SGV2Ah' http://127.0.0.1:8080/exist/apps/tuttle/git/hook```

### Generate the APIKey

`` GET ~/tuttle/{collection}/apikey``

The APIKey is generated and displayed once. If forgotten, it must be generated again.


### Display the Repository configuration and status

`` GET ~/tuttle/config ``

Displays the configuration and the state of the git repository.

States:
 - uptodate: Collection is up to date with GIT
 - behind: Collection is behind GIT and need an update
 - new: Collection is not a tuttle collection, full deployment is needed

```xml
<tuttle>
  <default>sample-collection-github</default>
  <repos>
    <repo type="github" url="https://github.com/Jinntec/tuttle-demo" ref="master" collection="sample-collection-github" status="uptodate"/>
    <repo type="gitlab" url="https://gitlab.com/tuttle-test/tuttle-demo.git" ref="master" collection="sample-collection-gitlab" status="uptodate"/>
  </repos>
</tuttle>
```

### Remove Lockfile

`` POST ~/tuttle/{collection}/lockfile ``

Remove lockfile after anything goes wrong.

#### Print Lockfile

`` GET ~/tuttle/{collection}/lockfile ``

The running task is stored in the lockfile. It ensures that two tasks do not run at the same time.


## Access token for gitservice (incomplete)

To talk to the configured gitservice Tuttle needs an access token. These can
be obtained from the respective service.

* see [Creating a personal access token](https://docs.github.com/en/github/authenticating-to-github/creating-a-personal-access-token) for github
* see [Personal access tokens](https://docs.gitlab.com/ee/user/profile/personal_access_tokens.html) for Gitlab

The key for the gitservice must be configured in Gitservice configuration as shown above.

## Roadmap

- [ ] DB to Git

## Honorable mentions:

![Horace Parnell Tuttle](src/resources/images/HPTuttle-1866.png)

[Horace Parnell Tuttle - American astronomer](http://www.klima-luft.de/steinicke/ngcic/persons/tuttle.htm)

[Archibald "Harry" Tuttle - Robert de Niro in Terry Gilliams' 'Brazil'](https://en.wikipedia.org/wiki/Brazil_(1985_film))
