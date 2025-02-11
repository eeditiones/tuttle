xquery version "3.1";

module namespace config="http://e-editiones.org/tuttle/config";

(:~
 : Configurtion file
 :)
declare variable $config:tuttle-config as element(tuttle) := doc("/db/apps/tuttle/data/tuttle.xml")/tuttle;

declare variable $config:default-ns := "http://e-editiones.org/tuttle/callbacks";

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

declare function config:get-callback($config as map(*)) as function(*)? {
    let $collection-config := $config:tuttle-config/repos/collection[@name = $config?collection]
    let $_ := util:log("info", $config?collection)
    let $_ := util:log("info", $config:tuttle-config/repos/collection/@name/string())
    let $_ := util:log("info", $collection-config)
    let $_ := util:log("info", $collection-config/callback)
    return
    if (empty($collection-config/callback))
    then (util:log("info", "NO CALLBACK DEFINED, STUPID!"))
    else if (count($collection-config/callback) ne 1)
    then error((), "More than one callback is not allowed: " || $collection-config/@name, $collection-config/callback)
    else (
        let $ns :=
            if ($collection-config/callback/@ns)
            then $collection-config/callback/@ns/string()
            else $config:default-ns

        let $qname :=
            try {
                QName($ns, $collection-config/callback/@name/string())
            } catch * {
                error((), "Callback QName problem: " || $collection-config/@name, $collection-config/callback)
            }

        let $import-options :=
            map { "location-hints" : 
                if (exists($collection-config/callback/@location))
                then $collection-config/callback/@location/string()
                else "/db/apps/tuttle/content/callbacks.xqm"
            }
        (: get function reference :)
        let $module := 
            try {
                fn:load-xquery-module($ns, $import-options)
            } catch * {
                error((), "Problem loading the callback for collection " || $collection-config/@name)
            }

        return 
            if (
                (: exists($module) and  :)
                (: map:contains($module, "functions") and
                map:contains($module?functions, $qname) and :)
                map:contains($module?functions?($qname), 2) (: arity 2 (map(*),map(*)) -> item()? :)
            ) then (
                util:log("info", $module),
                $module?functions?($qname)?2
            ) else (
                error((), "Callback function could not be found in module: " || $collection-config/@name, $collection-config/callback)
            )
    )
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

