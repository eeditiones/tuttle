xquery version "3.1";

module namespace config="http://exist-db.org/apps/tuttle/config";

(:~
 : Git configuration
 :)
declare variable $config:collections := map {
            "sample-collection-github" : map {
                "vcs" : "github",
                "baseurl" : "https://api.github.com/",
                "repo" : "tuttle-demo",
                "owner" : "Jinntec",
                "ref" : "master",
                "token" : "XXX",
                "hookuser" :  "admin",
                "hookpasswd" : ""
            },
            "sample-collection-gitlab" : map {
                "vcs" : "gitlab",
                "baseurl" : "https://gitlab.com/api/v4/",
                "project-id" : "2342555",
                "ref" : "master",
                "token" : "XXX",
                "hookuser" :  "admin",
                "hookpasswd" : ""

            }
        };

(:~
 : Defile default collection
 :)
declare variable $config:default-collection := "sample-collection-github";

(:~
 : Blacklist - these files are not checkout from git and are ignored
 :)
declare variable $config:blacklist := ["build.xml", "expath-pkg.xml", "repo.xml", "controller.xql", ".gitignore", "collection.xconf"];

(:~
 : Suffix of the checked out git statging collection 
 :)
declare variable $config:suffix := "-stage";

(:~
 : The running task is stored in the lockfile. It ensures that two tasks do not run at the same time. 
 :)
declare variable $config:lock := "git-lock.xml";

(:~
 : Prefix for collections
 :)
declare variable $config:prefix := "/db/apps";

(:~
 : The destination where the key for the webhook is stored.
 :)
declare variable $config:apikeys := "/db/system/auth/tuttle-token.xml" ;

(:~
 : DB User and Permissions as fallback if "permissions" not set in repo.xml
 :)
declare variable $config:sm := map {
    "user" : "nobody",
    "group" : "nogroup",
    "mode" : "rw-r--r--"
};

(:~ 
 : Custom Pre-install function - parameter destination-collection and stating-collection as full URI
:)
declare function config:pre-install ($collection as xs:string, $staging as xs:string) {
    true()
};