xquery version "3.1";

declare namespace api="http://exist-db.org/apps/tuttle/api";
declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";

import module namespace roaster="http://e-editiones.org/roaster";
import module namespace rutil="http://e-editiones.org/roaster/util";
import module namespace errors="http://e-editiones.org/roaster/errors";
import module namespace xmldb="http://exist-db.org/xquery/xmldb";
import module namespace compression="http://exist-db.org/xquery/compression";

import module namespace vcs="http://exist-db.org/apps/tuttle/vcs" at "vcs.xqm";
import module namespace app="http://exist-db.org/apps/tuttle/app" at "app.xql";
import module namespace config="http://exist-db.org/apps/tuttle/config" at "config.xql";


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
    <repo type="{$info?type}" url="{$info?url}"
        ref="{$info?ref}" collection="{$info?collection}"
        message="{$info?message}" status="{$info?status}" />
};

declare function api:collection-info ($collection as xs:string) as map(*) {
    let $collection-config := api:get-collection-config($collection)
    let $actions := vcs:get-actions($collection-config?vcs)
    let $deployed-commit-hash := doc($collection-config?path || "/gitsha.xml")/hash/value/string()
    let $info := map {
        'deployed': $deployed-commit-hash,
        'type': $collection-config?vcs,
        'ref': $collection-config?ref,
        'collection': $collection-config?collection
    }

    return
        try {
            let $url := $actions?get-url($collection-config)
            let $last-remote-commit := $actions?get-last-commit($collection-config)
            let $remote-short-sha := app:shorten-sha($last-remote-commit?sha)

            let $status :=
                if ($last-remote-commit?sha = "")
                then "error"
                else if (empty($deployed-commit-hash))
                then "new"
                else if ($deployed-commit-hash = $remote-short-sha)
                then "uptodate"
                else "behind"

            let $message :=
                if ($status = "error" )
                then "no commit on remote"
                else "remote found"

            return map:merge(( $info, map {
                'url': $url,
                'remote': $remote-short-sha,
                'message': $message,
                'status': $status
            }))
        }
        catch * {
            map:merge(( $info, map {
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
        let $actions := vcs:get-actions($collection-config?vcs)
        let $collection-staging := $collection-config?path || config:suffix() || "/gitsha.xml"

        let $last-remote-commit := $actions?get-last-commit($collection-config)

        return map {
            "remote-hash": $last-remote-commit?sha,
            "local-hash": app:production-sha($collection-config?collection),
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
declare function api:lock-remove($request as map(*)) {
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
declare function api:lock-print($request as map(*)) {
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
 : Clone repo to collection 
 :)
declare function api:git-pull($request as map(*)) {
    try {
        let $config := api:get-collection-config($request?parameters?collection)
        let $collection-staging := $config?path || config:suffix()
        let $collection-staging-sha := $config?path || config:suffix() || "/gitsha.xml"
        let $lockfile := $config?collection || "/" || config:lock()
        let $collection-destination := $config?collection

        return
            if (doc-available($lockfile)) then (
                map { "message" : doc($lockfile)/task/value/text() || " in progress" }
            )
            else (
                let $actions := vcs:get-actions($config?vcs)
                let $write-lock := app:lock-write($collection-destination, "git-pull")
                let $commit :=
                    if ($request?parameters?hash) then (
                        $request?parameters?hash
                    )
                    else (
                        $actions?get-last-commit($config)?sha
                    )

                let $clone := $actions?clone($config, $collection-staging, $commit)

                let $remove-lock := app:lock-remove($collection-destination)
                return $clone
            )
    }
    catch * {
        map { "message": $err:description }
    }
};

declare function api:git-pull-default($request as map(*)) {
    try {
        let $config := api:get-default-collection-config()
        let $collection-staging := config:prefix() || $config?collection || config:suffix()
        let $collection-staging-sha := $collection-staging || "/gitsha.xml"
        let $lockfile := $config?collection || "/" || config:lock()
        let $collection-destination := $config?collection

        return
            if (doc-available($lockfile)) then (
                map { "message" : doc($lockfile)/task/value/text() || " in progress" }
            )
            else (
                let $actions := vcs:get-actions($config?vcs)
                let $write-lock := app:lock-write($collection-destination, "git-pull")
                let $commit :=
                    if ($request?parameters?hash)
                    then $request?parameters?hash
                    else $actions?get-last-commit($config)?sha

                let $clone := $actions?clone($config, $collection-staging, $commit)

                let $remove-lock := app:lock-remove($collection-destination)
                return $clone
            )
    }
    catch * {
        map { "message": $err:description }
    }
};

(:~
 : Deploy  Repo 
:)

declare function api:git-deploy($request as map(*)) {
    try {
        let $config := api:get-collection-config($request?parameters?collection)
        let $collection-destination := $config?path
        let $collection-destination-sha := $config?path || "/gitsha.xml"
        let $lockfile := $config?path || "/" || config:lock()

        let $collection-staging := $config?collection || config:suffix() 
        let $collection-staging-uri := $config?path || config:suffix() 
        
        return
            if (not(xmldb:collection-available($collection-staging-uri)))
            then map { "message" : "Staging collection '" || $collection-staging-uri || "' does not exist" }
            else if (doc-available($lockfile))
            then map { "message" : doc($lockfile)/task/value/text() || " in progress" }
            else
                let $check-lock-dst :=
                    if (xmldb:collection-available($config?path))
                    then ()
                    else xmldb:create-collection(config:prefix(), $config?collection)

                let $write-lock := app:lock-write($config?path, "deploy")
                let $xar-list := xmldb:get-child-resources($collection-staging-uri)
                let $xar-check :=
                    if (not($xar-list = "expath-pkg.xml" and $xar-list = "repo.xml"))
                    then (
                        let $cleanup-col := app:cleanup-collection($config?collection, config:prefix())
                        let $cleanup-res := app:cleanup-resources($config?collection, config:prefix())
                        let $move-col := app:move-collections($collection-staging, $config?collection, config:prefix())
                        let $move-res := app:move-resources($collection-staging, $config?collection, config:prefix())
                        let $set-permissions := app:set-permission($config?collection)
                        return
                            map {
                                "sha" : app:production-sha($config?collection),
                                "message" : "success"
                            }
                    )
                    else (
                        let $remove-pkg :=
                            if (contains(repo:list(), $config?collection))
                            then (
                                let $package := doc(concat($config?path, "/expath-pkg.xml"))//@name/string()
                                let $undeploy := repo:undeploy($package)
                                return repo:remove($package) 
                            )
                            else ()
                            
                        let $xar :=
                            xmldb:store-as-binary(
                                $collection-staging-uri, "pkg.xar", 
                                compression:zip(xs:anyURI($collection-staging-uri),
                                true(), $collection-staging-uri)
                            )

                        let $install := repo:install-and-deploy-from-db(concat($collection-staging-uri, "/pkg.xar"))
                        return 
                            map {
                                "sha" : app:production-sha($config?collection),
                                "message" : "success"
                            }
                    )
                let $remove-staging := xmldb:remove($collection-staging-uri)
                let $remove-lock := app:lock-remove($collection-destination)
                return $xar-check
    }
    catch * {
        map {
            "_error": map {
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
        let $actions := vcs:get-actions($config?vcs)

        return $actions?get-commits($config, $request?parameters?count)
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
        let $actions := vcs:get-actions($config?vcs)

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
 : Trigger icremental update
 :)
declare function api:incremental($request as map(*)) as map(*) {
    try {
        let $config := api:get-collection-config($request?parameters?collection)
        let $drymode := $request?parameters?dry
        let $collection-path := $config?path
        let $lockfile := $collection-path || "/" || config:lock()
        let $collection-destination-sha := $collection-path || "/gitsha.xml"
        let $actions := vcs:get-actions($config?vcs)

        return
        if (not(xmldb:collection-available($collection-path))) then (
            map { "message" : "Destination collection not exist" }
        )
        else if (not(doc-available($collection-destination-sha))) then (
            map { "message" : "Collection not managed by Tuttle" }
        )
        else if (exists($drymode) and $drymode) then
            map {
                "changes" : $actions?incremental-dry($config, $config?collection),
                "message" : "success"
            }
        else if (doc-available($lockfile)) then (
            map { "message" : doc($lockfile)/task/value/text() || " in progress" }
        )
        else (
            let $write-lock := app:lock-write($collection-path, "incremental")
            let $incremental := $actions?incremental($config, $config?collection)
            let $remove-lock := app:lock-remove($collection-path)

            return
                map {
                    "sha" : app:production-sha($config?collection),
                    "message" : "success"
                }
        )
    }
    catch * {
        map {
            "message": $err:description,
            "_error": map {
                "code": $err:code, "description": $err:description, "value": $err:value, 
                "line": $err:line-number, "column": $err:column-number, "module": $err:module
            }
        }
    }
};

(:~
 : APIKey generation for webhooks
 :)
declare function api:api-keygen($request as map(*)) {
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
declare function api:hook($request as map(*)) {
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

                let $incremental := $actions?incremental($config, $config?collection)

                let $remove-lock := app:lock-remove($collection-path)

                return 
                    map {
                        "sha" : app:production-sha($config?collection),
                        "message" : "success"
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
        if (exists($collection) and not(empty($collection)))
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
