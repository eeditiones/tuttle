xquery version "3.1";

declare namespace api="http://exist-db.org/apps/tuttle/api";
declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";

import module namespace roaster="http://e-editiones.org/roaster";
import module namespace rutil="http://e-editiones.org/roaster/util";
import module namespace errors="http://e-editiones.org/roaster/errors";
import module namespace xmldb="http://exist-db.org/xquery/xmldb";
import module namespace compression="http://exist-db.org/xquery/compression";

import module namespace github="http://exist-db.org/apps/tuttle/github" at "github.xql";
import module namespace gitlab="http://exist-db.org/apps/tuttle/gitlab" at "gitlab.xql";
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
        <tuttle>
            <default>{config:default-collection()}</default>
            <repos>
            {for $collection in config:list-collections()
                let $col-config := config:collections($collection)
                let $collection-path := config:prefix() || "/" || $collection
                let $hash-staging := config:prefix() || "/" || $collection || config:suffix() || "/gitsha.xml"
                let $hash-deploy := config:prefix() || "/" || $collection || "/gitsha.xml"
                let $hash-git := if($col-config?vcs = "github") then github:get-lastcommit-sha($col-config)
                                    else gitlab:get-lastcommit-sha($col-config)
                let $status := if ($hash-git?sha = "" ) then
                                    "error"
                                else if (doc($hash-deploy)/hash/value/text() = $hash-git?sha) then
                                    "uptodate"
                                else if (empty(doc($hash-deploy)/hash/value/text()))  then
                                    "new"
                                else
                                    "behind"
                let $url := if($col-config?vcs = "github") then
                                github:get-url($col-config) 
                            else 
                                gitlab:get-url($col-config)
                let $message := if($status = "error" ) then
                                    concat($col-config?vcs, " error: ", $url?message)
                                else
                                    ""

                return <repo type="{$col-config?vcs}"
                    url='{if ($status = 'error') then "" else $url}'
                    ref="{$col-config?ref}"
                    collection="{$collection}"
                    message="{$message}"
                    status="{$status}"/>}
            </repos>
        </tuttle>
};

(:~ 
 : Post current hash and remote hash 
 :)
declare function api:get-hash($request as map(*)) {
    let $git-collection := if (not(exists($request?parameters?collection))) then  
        config:default-collection() else xmldb:decode-uri($request?parameters?collection) 
    let $config := config:collections($git-collection)
    let $collection := config:prefix() || "/" || $git-collection || "/gitsha.xml"
    let $collection-staging := config:prefix() || "/" || $git-collection || config:suffix() || "/gitsha.xml"

    return
        if (exists($config))  then (
            let $get-sha := if ($config?vcs = "github" ) then 
                github:get-lastcommit-sha($config) else gitlab:get-lastcommit-sha($config)
            return map {
                "remote-hash" : $get-sha?sha,
                "local-hash" : app:production-sha($git-collection),
                "local-staging-hash" : doc($collection-staging)/hash/value/text()
            }
        )
        else 
             map {"message" : "Config for '" || $git-collection || "' not exist."}
}; 

(:~
: Remove lockfile
:)
declare function api:lock-remove($request as map(*)) {
    let $git-collection := if (not(exists($request?parameters?collection))) then  
        config:default-collection() else xmldb:decode-uri($request?parameters?collection)
    let $config := config:collections($git-collection)
    let $lockfile-path := config:prefix() || "/" || $git-collection
    let $lockfile := $lockfile-path || "/" || config:lock()

    return
        if (exists($config))  then (
            if (exists(doc($lockfile))) then (
                let $remove := xmldb:remove($lockfile-path, config:lock())
                let $message := "lockfile removed: " || $lockfile 
                return
                    map { "message" : $message}
            )
            else
                let $message := "lockfile not exist"
                return
                    map { "message" : $message}
        )
        else 
             map {"message" : "Config for '" || $git-collection || "' not exist."}

};

(:~
: Print lockfile
:)
declare function api:lock-print($request as map(*)) {
    let $git-collection := if (not(exists($request?parameters?collection))) then  
        config:default-collection() else xmldb:decode-uri($request?parameters?collection) 
    let $config := config:collections($git-collection)
    let $lockfile-path := config:prefix() || "/" || $git-collection
    let $lockfile := $lockfile-path || "/" || config:lock()

    return
        if (exists($config))  then (
            if (exists(doc($lockfile))) then (
                let $message := doc($lockfile)/task/value/text() || " in progress"
                return
                    map { "message" : $message}
            )
            else
                let $message := "lockfile not exist"
                return
                    map { "message" : $message}
        )
        else 
             map {"message" : "Config for '" || $git-collection || "' not exist."}
};

(:~ 
 : Clone repo to collection 
 :)
declare function api:git-pull($request as map(*)) {
    let $git-collection := if (not(exists($request?parameters?collection))) then  
        config:default-collection() else xmldb:decode-uri($request?parameters?collection) 
    let $config := config:collections($git-collection)
    let $collection-staging := config:prefix() || "/" || $git-collection || config:suffix()
    let $collection-staging-sha := config:prefix() || "/" || $git-collection || config:suffix() || "/gitsha.xml"
    let $lockfile := config:prefix() || "/" || $git-collection || "/" || config:lock()
    let $collection-destination := config:prefix() || "/" || $git-collection

    return
        if (exists($config))  then (
            if (not(exists(doc($lockfile)))) then (
                let $write-lock := app:lock-write($collection-destination, "git-pull")
                let $clone := if ($config?vcs = "github" ) then (
                        if ($request?parameters?hash) then 
                            github:clone($config, $collection-staging, $request?parameters?hash) 
                        else 
                            github:clone($config, $collection-staging, github:get-lastcommit-sha($config)?sha) )
                    else (
                        if ($request?parameters?hash) then 
                            gitlab:clone($config, $collection-staging, $request?parameters?hash) 
                        else 
                            gitlab:clone($config, $collection-staging, gitlab:get-lastcommit-sha($config)?sha) )
                let $remove-lock := app:lock-remove($collection-destination)
                return $clone
            )
            else
                let $message := doc($lockfile)/task/value/text() || " in progress"
                return
                    map { "message" : $message}
        )
        else 
             map {"message" : "Config for '" || $git-collection || "' not exist."}
};

(:~
 : Deploy  Repo 
:)

declare function api:git-deploy($request as map(*)) {
    let $git-collection := if (not(exists($request?parameters?collection))) then  
        config:default-collection() else xmldb:decode-uri($request?parameters?collection) 
    let $config := config:collections($git-collection)
    let $collection-staging := $git-collection || config:suffix()
    let $collection-staging-uri := config:prefix() || "/" || $collection-staging 
    let $collection-destination := config:prefix() || "/" || $git-collection
    let $collection-destination-sha := $collection-destination || "/gitsha.xml"
    let $lockfile := $collection-destination || "/" || config:lock()
    
    return
        if (exists($config))  then (
            try {
                if (not(xmldb:collection-available($collection-staging-uri))) then (
                    map { "message" : "Staging collection '" || $collection-staging || "' does not exist" }
                )
                else if (exists(doc($lockfile))) then (
                    map { "message" : doc($lockfile)/task/value/text() || " in progress" }
                )
                else (
                    let $check-lock-dst := if (xmldb:collection-available($collection-destination)) then ()
                    else (
                        xmldb:create-collection(config:prefix(), $git-collection)
                    ) 
                    let $write-lock := app:lock-write($collection-destination, "deploy")
                    let $xar-list := xmldb:get-child-resources($collection-staging-uri)
                    let $xar-check := if (not($xar-list = "expath-pkg.xml" and $xar-list = "repo.xml")) then (
                            let $cleanup-col := app:cleanup-collection($git-collection, config:prefix())
                            let $cleanup-res := app:cleanup-resources($git-collection, config:prefix())
                            let $move-col := app:move-collections($collection-staging, $git-collection, config:prefix())
                            let $move-res := app:move-resources($collection-staging, $git-collection, config:prefix())
                            let $set-permissions := app:set-permission($git-collection)
                            return 
                            map {
                                        "sha" : app:production-sha($git-collection),
                                        "message" : "success"
                                }
                        )
                        else (
                            let $remove-pkg := if (contains(repo:list(), $git-collection)) then (
                                let $package := doc(concat($collection-destination, "/expath-pkg.xml"))//@name/string()
                                let $undeploy := repo:undeploy($package)
                                return repo:remove($package) 
                            )
                            else ()
                            let $xar := xmldb:store-as-binary($collection-staging-uri, "pkg.xar", 
                                compression:zip(xs:anyURI($collection-staging-uri),true(), $collection-staging-uri))
                            let $install := repo:install-and-deploy-from-db(concat($collection-staging-uri, "/pkg.xar"))
                            return 
                                map {
                                    "sha" : app:production-sha($git-collection),
                                    "message" : "success"
                            }                            
                        )
                    let $remove-staging := xmldb:remove($collection-staging-uri)
                    let $remove-lock := app:lock-remove($collection-destination)
                    return $xar-check
                )
            }
            catch * {
                map {
                        "_error": map {
                            "code": $err:code, "description": $err:description, "value": $err:value, 
                            "line": $err:line-number, "column": $err:column-number, "module": $err:module
                        }
                }
            }
        )
        else 
             map {"message" : "Config for '" || $git-collection || "' not exist."}
};
 
(:~
 : get commits and comments 
 :)
declare function api:get-commit($request as map(*)) {
    let $git-collection := if (not(exists($request?parameters?collection))) then  
        config:default-collection() else xmldb:decode-uri($request?parameters?collection) 
    let $config := config:collections($git-collection)

    return
        if (exists($config))  then (
            if ($config?vcs = "github" ) then (
                if ($request?parameters?count) then 
                    github:get-commits($config, $request?parameters?count)
                else
                    github:get-commits($config))
            else (
                if ($request?parameters?count) then 
                    gitlab:get-commits($config, $request?parameters?count)
                else
                    gitlab:get-commits($config))
        )
        else 
             map {"message" : "Config for '" || $git-collection || "' not exist."}
};

(:~ 
 : Trigger icremental update
 :)
declare function api:incremental($request as map(*)) {
    let $git-collection := if (not(exists($request?parameters?collection))) then  
        config:default-collection() else xmldb:decode-uri($request?parameters?collection) 
    let $config := config:collections($git-collection)
    let $collection-path := config:prefix() || "/" || $git-collection
    let $lockfile := $collection-path || "/" || config:lock()
    let $collection-destination-sha := $collection-path || "/gitsha.xml"

    return
        if (exists($config))  then (
            try {
                if (xmldb:collection-available($collection-path)) then (
                    if (exists(doc($collection-destination-sha))) then (
                        if (not(exists(doc($lockfile)))) then (
                            let $write-lock := app:lock-write($collection-path, "incremental")
                            let $incremental := 
                                if ($config?vcs = "github" ) then 
                                    github:incremental($config, $git-collection)
                            else 
                                    gitlab:incremental($config, $git-collection)
                            let $remove-lock := app:lock-remove($collection-path)
                            return 
                                map {
                                    "sha" : app:production-sha($git-collection),
                                    "message" : "success"
                                })
                        else (
                            let $message := doc($lockfile)/task/value/text() || " in progress"
                            return
                                map { "message" : $message}
                        )
                    )
                    else (
                        map { 
                            "message" : "Collection not managed by Tuttle"
                        }
                    )
                )
                else (
                    map { 
                        "message" : "Destination collection not exist"
                    }
                )
            }
            catch * {
                map {
                        "_error": map {
                            "code": $err:code, "description": $err:description, "value": $err:value, 
                            "line": $err:line-number, "column": $err:column-number, "module": $err:module
                        }
                }
            }
        )
        else 
             map {"message" : "Config for '" || $git-collection || "' not exist."}
};

(:~
 : APIKey generation for webhooks
 :)
declare function api:api-keygen($request as map(*)) {
    let $git-collection :=
        if (not(exists($request?parameters?collection)))
        then config:default-collection()
        else xmldb:decode-uri($request?parameters?collection)
    let $config := config:collections($git-collection)

    return
        if (exists($config))  then (
            let $apikey := app:random-key(42)
            let $write-apikey := app:write-apikey($git-collection,  $apikey)
            return 
                map {
                    "APIKey" : $apikey
                }
        )
        else 
             map {"message" : "Config for '" || $git-collection || "' not exist."}
};

(:~ 
 : Webhook function 
 :)
declare function api:hook($request as map(*)) {
    let $git-collection := if (not(exists($request?parameters?collection))) then  
        config:default-collection() else xmldb:decode-uri($request?parameters?collection) 
    let $config := config:collections($git-collection)
    
    return
        if (exists($config))  then (
            let $apikey := doc(config:apikeys())//apikeys/collection[name = $git-collection]/key/text()
            return 
                if ($apikey) then (
                    let $apikey-header := 
                        if ($config?vcs = "github" ) then
                            if (github:check-signature($git-collection, request:get-header("X-Hub-Signature-256"), util:binary-to-string(request:get-data()))) then
                                $apikey
                            else ()
                        else
                            request:get-header("X-Gitlab-Token")
                    return
                        if ($apikey-header = $apikey) then (
                            let $collection-path := config:prefix() || "/" || $git-collection
                            let $lockfile := $collection-path || "/" || config:lock()
                            let $collection-destination-sha := $collection-path || "/gitsha.xml"
                            let $login := xmldb:login($collection-path, $config?hookuser, $config?hookpasswd)

                            return
                                if (not(exists(doc($lockfile)))) then (
                                    let $write-lock := app:lock-write($collection-path, "hook")
                                    let $incremental := 
                                        if ($config?vcs = "github" ) then
                                            github:incremental($config, $git-collection)
                                        else
                                            gitlab:incremental($config, $git-collection)
                                    let $remove-lock := app:lock-remove($collection-path)
                                    return 
                                        map {
                                            "sha" : app:production-sha($git-collection),
                                            "message" : "success"
                                        })
                                else (
                                    let $message := doc($lockfile)/task/value/text() || " in progress"
                                    return
                                        map { "message" : $message}
                                ))
                    else (
                        roaster:response(401, "Unauthorized")
                    ))
            else (
                map {
                    "message" : "apikey not exist"
                }
            )
        )
        else 
             map {"message" : "Config for '" || $git-collection || "' not exist."}
};

(:~
 : You can add application specific route handlers here.
 : Having them in imported modules is preferred.s
 :)

declare function api:date($request as map(*)) {
    $request?parameters?date instance of xs:date and
    $request?parameters?dateTime instance of xs:dateTime
};

(:~
 : An example how to throw a dynamic custom error (error:NOT_FOUND_404)
 : This error is handled in the router
 :)
declare function api:error-triggered($request as map(*)) {
    error($errors:NOT_FOUND, "document not found", "error details")
};

(:~
 : calling this function will throw dynamic XQuery error (err:XPST0003)
 :)
declare function api:error-dynamic($request as map(*)) {
    util:eval('1 + $undefined')
};

(:~
 : Handlers can also respond with an error directly 
 :)
declare function api:error-explicit($request as map(*)) {
    roaster:response(403, "application/xml", <forbidden/>)
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
