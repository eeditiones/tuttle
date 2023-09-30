xquery version "3.1";

module namespace config="http://exist-db.org/apps/tuttle/config";

(:~
 : Configurtion file
 :)
declare variable $config:tuttle-config as element(tuttle) := doc("/db/apps/tuttle/data/tuttle.xml")/tuttle;

(:~
 : Git configuration
 :)
declare function config:collections($collection as xs:string) as map(*)? {
    let $collection-config := $config:tuttle-config/repos/collection[@name = $collection]

    return
        if (empty($collection-config))
        then (
            (: error((), "Collection config for '" || $collection || "' not found!") :)
        )
        else map {
            "repo" : $collection-config/repo/string(),
            "owner" : $collection-config/owner/string(),
            "project-id" : $collection-config/project-id/string(),
            "vcs": $collection-config/type/string(),
            "baseurl": $collection-config/baseurl/string(),
            "ref": $collection-config/ref/string(),
            "collection": $collection-config/@name/string(),
            "path": config:prefix() || $collection,
            "hookuser":  $collection-config/hookuser/string(),
            (: be careful never to expose these :)
            "hookpasswd": $collection-config/hookpasswd/string(),
            "token": config:token($collection-config)
        }
};

declare %private function config:token($collection-config as element(collection)) as xs:string? {
    let $env-var := "tuttle_token_" || replace($collection-config/@name/string(), "-", "_")
    let $token-env := environment-variable($env-var)

    return
        if (exists($token-env) and $token-env ne "")
        then $token-env
        else $collection-config/token/string()
};

(:~
 : List collection names
 :)
declare function config:collection-config-available($collection as xs:string) as xs:boolean {
    exists($config:tuttle-config/repos/collection[@name = $collection])
};

(:~
 : List collection names
 :)
declare function config:list-collections() {
    $config:tuttle-config/repos/collection/@name/string()
};


(:~
 : Defile default collection
 :)
declare function config:default-collection(){
    $config:tuttle-config/repos/collection[default="true"]/@name/string()
};

(:~
 : Blacklist - these files are not checkout from git and are ignored
 :)
declare function config:blacklist(){
    $config:tuttle-config/blacklist/file/string()
};

(:~
 : Suffix of the checked out git statging collection 
 :)
declare function config:suffix(){
    $config:tuttle-config/config/@suffix/string()
};

(:~
 : The running task is stored in the lockfile. It ensures that two tasks do not run at the same time. 
 :)
declare function config:lock(){
    $config:tuttle-config/config/@lock/string()
};

(:~
 : Prefix for collections
 :)
declare function config:prefix(){
    $config:tuttle-config/config/@prefix/string()
};

(:~
 : The destination where the key for the webhook is stored.
 :)
declare function config:apikeys(){
    $config:tuttle-config/config/@apikeys/string()
};

(:~
 : DB User and Permissions as fallback if "permissions" not set in repo.xml
 :)
declare function config:sm(){
    let $sm := $config:tuttle-config/config/sm

    return map {
        "user" : $sm/@user/string(),
        "group" : $sm/@group/string(),
        "mode" : $sm/@mode/string()
    }
};

