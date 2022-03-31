xquery version "3.1";

module namespace config="http://exist-db.org/apps/tuttle/config";

(:~
 : Git configuration
 :)
declare variable $config:collections := map {
            "sample-collection-github" : map {
                "vcs" : "github",
                "baseurl" : "https://api.github.com/",
                "repo" : "tuttle-sample-data",
                "owner" : "tuttle-sample-data",
                "ref" : "master",
                "token" : "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",
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
declare variable $config:blacklist := [".existdb.json", "build.xml", "README.md", ".gitignore", "expath-pkg.xml.tmpl", "repo.xml.tmpl", "build.properties.xml"];

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

