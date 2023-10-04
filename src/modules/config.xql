xquery version "3.1";

module namespace config="http://e-editiones.org/tuttle/config";

(:~
 : Configurtion file
 :)
declare variable $config:tuttle-config as element(tuttle) := doc("/db/apps/tuttle/data/tuttle.xml")/tuttle;

(:~
 : Git configuration
 :)
declare function config:collections($collection-name as xs:string) as map(*)? {
    let $collection-config := $config:tuttle-config/repos/collection[@name = $collection-name]
    let $path := config:prefix() || $collection-name

    return
        if (empty($collection-config))
        then (
            (: error((), "Collection config for '" || $collection || "' not found!") :)
        )
        else map {
            "repo" : $collection-config/repo/string(),
            "owner" : $collection-config/owner/string(),
            "project-id" : $collection-config/project-id/string(),
            "ref": $collection-config/ref/string(),
            "collection": $collection-name,

            "type": $collection-config/type/string(),
            "baseurl": $collection-config/baseurl/string(),
            "hookuser":  $collection-config/hookuser/string(),

            "path": $path,
            "deployed": config:deployed-sha($path),

            (: be careful never to expose these :)
            "hookpasswd": $collection-config/hookpasswd/string(),
            "token": config:token($collection-config)
        }
};

(:~
: Which commit is deployed?
:)
declare function config:deployed-sha($path as xs:string) as xs:string? {
    if (doc-available($path || "/gitsha.xml"))
    then doc($path || "/gitsha.xml")/hash/value/string()
    else ()
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
declare function config:list-collections() as xs:string* {
    $config:tuttle-config/repos/collection/@name/string()
};


(:~
 : get default collection
 :)
declare function config:default-collection() as xs:string? {
    $config:tuttle-config/repos/collection[default="true"]/@name/string()
};

(:~
 : ignore - these files are not checkout from git and are ignored
 :)
declare function config:ignore() as xs:string* {
    $config:tuttle-config/ignore/file/string()
};

(:~
 : Suffix of the checked out git statging collection 
 :)
declare function config:suffix() as xs:string {
    $config:tuttle-config/config/@suffix/string()
};

(:~
 : The running task is stored in the lockfile. It ensures that two tasks do not run at the same time. 
 :)
declare function config:lock() as xs:string {
    $config:tuttle-config/config/@lock/string()
};

(:~
 : Prefix for collections
 :)
declare function config:prefix() as xs:string {
    $config:tuttle-config/config/@prefix/string()
};

(:~
 : The destination where the key for the webhook is stored.
 :)
declare function config:apikeys() as xs:string* {
    $config:tuttle-config/config/@apikeys/string()
};

(:~
 : DB User and Permissions as fallback if "permissions" not set in repo.xml
 :)
declare function config:sm() as map(*) {
    let $sm := $config:tuttle-config/config/sm

    return map {
        "user" : $sm/@user/string(),
        "group" : $sm/@group/string(),
        "mode" : $sm/@mode/string()
    }
};

