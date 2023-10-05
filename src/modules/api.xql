xquery version "3.1";

declare namespace api="http://exist-db.org/apps/tuttle/api";
declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";

import module namespace roaster="http://e-editiones.org/roaster";
import module namespace rutil="http://e-editiones.org/roaster/util";
import module namespace errors="http://e-editiones.org/roaster/errors";
import module namespace xmldb="http://exist-db.org/xquery/xmldb";
import module namespace compression="http://exist-db.org/xquery/compression";

import module namespace vcs="http://e-editiones.org/tuttle/vcs" at "vcs.xqm";
import module namespace app="http://e-editiones.org/tuttle/app" at "app.xql";
import module namespace config="http://e-editiones.org/tuttle/config" at "config.xql";
import module namespace collection="http://existsolutions.com/modules/collection" at "collection.xqm";


(:~
 : list of definition files to use
 :)
declare variable $api:definitions := ("api.json");

(:~
 : Post git status 
 :)
declare function api:get-status($request as map(*)) {
    if (contains(request:get-header('Accept'), 'application/json'))
    then map {
        'default': config:default-collection(),
        'repos': array {
            config:list-collections() ! api:collection-info(.)
        }
    }
    else
        <tuttle>
            <default>{config:default-collection()}</default>
            <repos>{
                config:list-collections()
                ! api:collection-info(.)
                ! api:repo-xml(.)
            }</repos>
        </tuttle>
};

declare function api:repo-xml ($info as map(*)) as element(repo) {
    element repo {
        map:for-each($info, function ($name as xs:string, $value) as attribute() {
            attribute { $name } { $value }
        })
    }
};

declare function api:collection-info ($collection as xs:string) as map(*) {
    let $collection-config := api:get-collection-config($collection)
    (: hide passwords and tokens :)
    let $masked := map:remove($collection-config, ("hookpasswd", "token"))

    return
        try {
            let $actions := vcs:get-actions($collection-config?type)
            let $url := $actions?get-url($collection-config)
            let $last-remote-commit := $actions?get-last-commit($collection-config)
            let $remote-short-sha := app:shorten-sha($last-remote-commit?sha)

            let $status :=
                if ($remote-short-sha = "")
                then "error"
                else if (empty($collection-config?deployed))
                then "new"
                else if ($collection-config?deployed = $remote-short-sha)
                then "uptodate"
                else "behind"

            let $message :=
                if ($status = "error" )
                then "no commit on remote"
                else "remote found"

            return map:merge(( $masked, map {
                'url': $url,
                'remote': $remote-short-sha,
                'message': $message,
                'status': $status
            }))
        }
        catch * {
            map:merge(( $masked, map {
                'message': $err:description,
                'status': 'error'
            }))
        }
};

(:~ 
 : Post current hash and remote hash 
 :)
declare function api:get-hash($request as map(*)) as map(*) {
    try {
        let $collection-config := api:get-collection-config($request?parameters?collection)
        let $actions := vcs:get-actions($collection-config?type)
        let $collection-staging := $collection-config?path || config:suffix() || "/gitsha.xml"

        let $last-remote-commit := $actions?get-last-commit($collection-config)

        return map {
            "remote-hash": $last-remote-commit?sha,
            "local-hash": $collection-config?deployed,
            "local-staging-hash": doc($collection-staging)/hash/value/text()
        }
    }
    catch * {
        map { "message": $err:description }
    }
}; 

(:~
: Remove lockfile
:)
declare function api:lock-remove($request as map(*)) as map(*) {
    try {
        let $config := api:get-collection-config($request?parameters?collection)
        let $lockfile := $config?path || "/" || config:lock()

        let $message :=
            if (not(doc-available($lockfile)))
            then "Lockfile " || $lockfile || " does not exist"
            else
                let $remove := xmldb:remove($config?path, config:lock())
                return "Removed lockfile: " || $lockfile

        return map { "message": $message }
    }
    catch * {
        map { "message": $err:description }
    }
};

(:~
: Print lockfile
:)
declare function api:lock-print($request as map(*)) as map(*) {
    try {
        let $config := api:get-collection-config($request?parameters?collection)
        let $lockfile := $config?path || '/' || config:lock()
        let $message :=
            if (not(doc-available($lockfile)))
            then "No lockfile for '" || $config?collection || "' found."
            else doc($lockfile)/task/value/string() || " in progress"

        return map { "message": $message }
    }
    catch * {
        map { "message": $err:description }
    }
};

(:~
 : Load repository state to staging collection
 :)
declare function api:git-pull($request as map(*)) as map(*) {
    api:pull(
        api:get-collection-config($request?parameters?collection),
        $request?parameters?hash)
};

(:~
 : Load default repository state to staging collection
 :)
declare function api:git-pull-default($request as map(*)) as map(*) {
    api:pull(
        api:get-default-collection-config(),
        $request?parameters?hash)
};

(:~
 : Load repository state to staging collection
 :)
declare %private function api:pull($config as map(*), $hash as xs:string?) as map(*) {
    try {
        if (doc-available($config?collection || "/" || config:lock())) then (
            map { "message" : doc($config?collection || "/" || config:lock())/task/value/text() || " in progress" }
        )
        else (
            let $actions := vcs:get-actions($config?type)
            let $write-lock := app:lock-write($config?collection, "git-pull")

            let $staging-collection := $config?path || config:suffix()

            let $delete-collection := collection:remove($staging-collection, true())
            let $create-collection := collection:create($staging-collection)

            let $sha :=
                if (exists($hash)) then (
                    $hash
                ) else (
                    $actions?get-last-commit($config)?sha
                )

            let $write-sha := app:write-sha($staging-collection, $sha)

            let $zip := $actions?get-archive($config, $sha)
            let $extract := app:extract-archive($zip, $staging-collection)

            let $remove-lock := app:lock-remove($config?collection)
            return map {
                "message" : "success",
                "hash": $sha,
                "collection": $staging-collection
            }
        )
    }
    catch * {
        map {
            "message": $err:description,
            "error": map {
                "code": $err:code, "description": $err:description, "value": $err:value, 
                "line": $err:line-number, "column": $err:column-number, "module": $err:module
            }
        }
    }
};

(:~
 : Deploy  Repo 
:)

declare function api:git-deploy($request as map(*)) as map(*) {
    try {
        let $config := api:get-collection-config($request?parameters?collection)
        let $collection-destination := $config?path
        let $collection-destination-sha := $config?path || "/gitsha.xml"
        let $lockfile := $config?path || "/" || config:lock()

        let $collection-staging := $config?collection || config:suffix() 
        let $collection-staging-uri := $config?path || config:suffix() 
        
        let $ensure-destination-collection := collection:create($config?path)
        return
            if (not(xmldb:collection-available($collection-staging-uri)))
            then map { "message" : "Staging collection '" || $collection-staging-uri || "' does not exist!" }
            else if (doc-available($lockfile))
            then map { "message" : doc($lockfile)/task/value/text() || " in progress!" }
            else if (exists($ensure-destination-collection?error))
            then map { "message" : "Could not create destination collection!", "error": $ensure-destination-collection?error }
            else
                let $write-lock := app:lock-write($config?path, "deploy")
                let $is-expath-package := xmldb:get-child-resources($collection-staging-uri) = ("expath-pkg.xml", "repo.xml")
                let $deploy :=
                    if ($is-expath-package)
                    then (
                        let $package := doc(concat($config?path, "/expath-pkg.xml"))//@name/string()
                        let $remove-pkg :=
                            if ($package = repo:list())
                            then (
                                let $undeploy := repo:undeploy($package)
                                let $remove := repo:remove($package)
                                return ($undeploy, $remove)
                            )
                            else ()
                            
                        let $xar :=
                            xmldb:store-as-binary(
                                $collection-staging-uri, "pkg.xar", 
                                compression:zip(xs:anyURI($collection-staging-uri), true(), $collection-staging-uri))

                        let $install := repo:install-and-deploy-from-db($xar)
                        return "package installation"
                    )
                    else (
                        let $cleanup-col := app:cleanup-collection($config?collection, config:prefix())
                        let $cleanup-res := app:cleanup-resources($config?collection, config:prefix())
                        let $move-col := app:move-collections($collection-staging, $config?collection, config:prefix())
                        let $move-res := app:move-resources($collection-staging, $config?collection, config:prefix())
                        let $set-permissions := app:set-permission($config?path)
                        return "data move"
                    )

                let $remove-staging := collection:remove($collection-staging-uri, true())
                let $remove-lock := app:lock-remove($collection-destination)

                return map {
                    "hash": config:deployed-sha($config?path),
                    "message": "success"
                }

    }
    catch * {
        map {
            "message": $err:description,
            "error": map {
                "code": $err:code, "description": $err:description, "value": $err:value, 
                "line": $err:line-number, "column": $err:column-number, "module": $err:module
            }
        }
    }
};
 
(:~
 : get commits and comments 
 :)
declare function api:get-commits($request as map(*)) as map(*) {
    try {
        let $config := api:get-collection-config($request?parameters?collection)
        let $actions := vcs:get-actions($config?type)

        return map {
            'commits': $actions?get-commits($config, $request?parameters?count)
        }
    }
    catch * {
        map {
            "message": $err:description,
            "code": $err:code, "value": $err:value, 
            "line": $err:line-number, "column": $err:column-number, "module": $err:module,
            "request": map:remove($request, 'spec')
         }
    }
};

(:~
 : get commits and comments 
 :)
declare function api:get-commits-default($request as map(*)) as map(*) {
    try {
        let $config := api:get-default-collection-config()
        let $actions := vcs:get-actions($config?type)

        return map {
            'commits': $actions?get-commits($config, $request?parameters?count)
        }
    }
    catch * {
        map {
            "message": $err:description,
            "code": $err:code, "value": $err:value, 
            "line": $err:line-number, "column": $err:column-number, "module": $err:module,
            "request": map:remove($request, 'spec')
         }
    }
};

(:~ 
 : Trigger incremental update
 :)
declare function api:incremental($request as map(*)) as map(*) {
    try {
        let $config := api:get-collection-config($request?parameters?collection)
        let $lockfile := $config?path || "/" || config:lock()
        let $actions := vcs:get-actions($config?type)

        return
            if (not(xmldb:collection-available($config?path))) then (
                map { "message" : "Destination collection not exist" }
            )
            else if (empty($config?deployed)) then (
                map { "message" : "Collection not managed by Tuttle" }
            )
            else if ($request?parameters?dry) then
                map {
                    "changes" : $actions?incremental-dry($config),
                    "message" : "dry-run"
                }
            else if (doc-available($lockfile)) then (
                map { "message" : doc($lockfile)/task/value/text() || " in progress" }
            )
            else (
                let $write-lock := app:lock-write($config?path, "incremental")
                let $incremental := $actions?incremental($config)
                let $errors := some $a in ($incremental?new?*, $incremental?del?*)?2 satisfies not($a)
                let $remove-lock := app:lock-remove($config?path)

                return
                    map {
                        "hash": config:deployed-sha($config?path),
                        "message": if ($errors) then "ended with errors" else "success",
                        "changes": $incremental
                    }
            )
    }
    catch * {
        map {
            "message": $err:description,
            "error": map {
                "code": $err:code, "description": $err:description, "value": $err:value, 
                "line": $err:line-number, "column": $err:column-number, "module": $err:module
            }
        }
    }
};

(:~
 : APIKey generation for webhooks
 :)
declare function api:api-keygen($request as map(*)) as map(*) {
    try {
        let $config := api:get-collection-config($request?parameters?collection)
        let $apikey := app:random-key(42)
        let $write-apikey := app:write-apikey($config?collection,  $apikey)

        return map { "APIKey" : $apikey }
    }
    catch * {
        map { "message": $err:description }
    }
};

(:~ 
 : Webhook function 
 :)
declare function api:hook($request as map(*)) as map(*) {
    try {
        let $config := api:get-collection-config($request?parameters?collection)
        let $apikey := doc(config:apikeys())//apikeys/collection[name = $config?collection]/key/string()
        let $lockfile := $config?path || "/" || config:lock()
        return
            if (empty($apikey)) then (
                map { "message": "apikey does not exist" }
            )
            else if (doc-available($lockfile)) then (
                map { "message" : doc($lockfile)/task/value/text() || " in progress" }
            )
            else if (not($actions?check-signature($config?collection, $apikey))) then (
                roaster:response(401, "Unauthorized")
            )
            else (
                let $collection-destination-sha := $config?path || "/gitsha.xml"
                let $login := xmldb:login($config?path, $config?hookuser, $config?hookpasswd)
                let $write-lock := app:lock-write($config?path, "hook")

                let $incremental := $actions?incremental($config)

                let $remove-lock := app:lock-remove($collection-path)

                return
                    map {
                        "sha": config:deployed-sha($config?path),
                        "message": "success"
                    }
            )
    }
    catch * {
        map { "message": $err:description }
    }
};


(:~
 : This is used as an error-handler in the API definition 
 :)
declare function api:handle-error($error as map(*)) as element(html) {
    <html>
        <body>
            <h1>Error [{$error?code}]</h1>
            <p>{
                if (map:contains($error, "module"))
                then ``[An error occurred in `{$error?module}` at line `{$error?line}`, column `{$error?column}`]``
                else "An error occurred!"
            }</p>
            <h2>Description</h2>
            <p>{$error?description}</p>
        </body>
    </html>
};

declare %private function api:get-default-collection-config() as map(*)? {
    config:collections(config:default-collection())
};

declare %private function api:get-collection-config($collection as xs:string?) as map(*)? {
    let $git-collection :=
        if (exists($collection) and $collection ne '')
        then xmldb:decode-uri($collection)
        else config:default-collection()

    let $collection-config := config:collections($git-collection)
    
    return
        if (empty($git-collection))
        then error((), "git collection not found!")
        else if (empty($collection-config))
        then error((), "collection config not found!")
        else $collection-config
};

(: end of route handlers :)

(:~
 : This function "knows" all modules and their functions
 : that are imported here 
 : You can leave it as it is, but it has to be here
 :)
declare function api:lookup ($name as xs:string) {
    function-lookup(xs:QName($name), 1)
};

roaster:route($api:definitions, api:lookup#1)
