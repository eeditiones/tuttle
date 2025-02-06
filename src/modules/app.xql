xquery version "3.1";

module namespace app="http://e-editiones.org/tuttle/app";

import module namespace xmldb="http://exist-db.org/xquery/xmldb";
import module namespace http="http://expath.org/ns/http-client";
import module namespace compression="http://exist-db.org/xquery/compression";
import module namespace repo="http://exist-db.org/xquery/repo";
import module namespace sm="http://exist-db.org/xquery/securitymanager";

import module namespace collection="http://existsolutions.com/modules/collection";

import module namespace config="http://e-editiones.org/tuttle/config" at "config.xql";

declare function app:extract-archive($zip as xs:base64Binary, $collection as xs:string) {
    compression:unzip($zip, 
        app:unzip-filter#3, config:ignore(),
        app:unzip-store#4, $collection)
};

(:~
 : Unzip helper function
 :)
declare function app:unzip-store($path as xs:string, $data-type as xs:string, $data as item()?, $base as xs:string) as map(*) {
    if ($data-type = 'folder') then (
        let $create := collection:create($base || "/" || substring-after($path, '/'))
        return map { "path": $path }
    ) else (
        try {
            let $resource := app:file-to-resource($base, substring-after($path, '/'))
            let $collection-check := collection:create($resource?collection)
            let $store := xmldb:store($resource?collection, $resource?name, $data)
            return map { "path": $path }
        }
        catch * {
            map { "path": $path, "error": $err:description }
        }
    )
};

(:~
 : Filter out ignored resources
 : returning true() _will_ extract the file or folder
 :)
declare function app:unzip-filter($path as xs:string, $data-type as xs:string, $ignore as xs:string*) as xs:boolean { 
    not(substring-after($path, '/') = $ignore)
};

(:~
 : Move staging collection to final collection
 :)
declare function app:move-collection($collection-source as xs:string, $collection-target as xs:string) {
    xmldb:get-child-collections($collection-source) 
        ! xmldb:move($collection-source || "/" || ., $collection-target),
    xmldb:get-child-resources($collection-source) 
        ! xmldb:move($collection-source, $collection-target, .)
};

(:~ 
 : Cleanup destination collection - delete collections from target collection
 :)
declare function app:cleanup-collection($collection as xs:string) {
    let $ignore := (config:ignore(), config:lock())
    return (
        xmldb:get-child-collections($collection)[not(.= $ignore)]
            ! xmldb:remove($collection || "/" || .),
        xmldb:get-child-resources($collection)[not(.= $ignore)]
            ! xmldb:remove($collection, .)
    )
};

(:~
 : Random apikey generator
 :)
declare function app:random-key($length as xs:int) {
    let $secret :=
        for $loop in 1 to $length 
            let $random1 := util:random(9)+48
            let $random2 := util:random(25)+65
            let $random3 := util:random(25)+97
            return 
                if (util:random(2) = 1) then
                    fn:codepoints-to-string(($random2))
                else if (util:random(2) = 1) then 
                    fn:codepoints-to-string(($random3))
                else
                    fn:codepoints-to-string(($random1))
                
    return string-join($secret)
};

(:~ 
 : Write api key to config:apikeys()
 :)
declare function app:write-apikey($collection as xs:string, $apikey as xs:string) {
    try {
        let $collection-prefix := tokenize(config:apikeys(), '[^/]+$')[1]
        let $apikey-resource := xmldb:encode(replace(config:apikeys(), $collection-prefix, ""))
        let $collection-check := collection:create($collection-prefix)

        return 
            if (doc(config:apikeys())//apikeys/collection[name = $collection]/key/text()) then
                update replace doc(config:apikeys())//apikeys/collection[name = $collection]/key with <key>{$apikey}</key>
            else if (doc(config:apikeys())//apikeys) then
                let $add := <collection><name>{$collection}</name><key>{$apikey}</key></collection>
                return update insert $add into doc(config:apikeys())//apikeys
            else
                let $add := <apikeys><collection><name>{$collection}</name><key>{$apikey}</key></collection></apikeys>
                let $store := xmldb:store($collection-prefix, $apikey-resource, $add)
                let $chmod := sm:chmod(config:apikeys(), "rw-r-----")
                return $store
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
 : Write lock file
 :)
declare function app:lock-write($collection as xs:string, $task as xs:string) {
    if (xmldb:collection-available($collection)) then (
        xmldb:store($collection, config:lock(),
            <task><value>{ $task }</value></task>)
    ) else ()
};

(:~
 : Delete lock file
 :)
declare function app:lock-remove($collection as xs:string) {
    if (doc-available($collection || "/" || config:lock())) then (
        xmldb:remove($collection, config:lock())
    ) else ()
};

(:~
 : Set permissions to collection recursively 
 :)
declare function app:set-permission($collection as xs:string) {
    let $permissions := app:get-permissions($collection)
    let $callback := app:set-permission(?, ?, $permissions)

    return
        collection:scan($collection, $callback)
};

declare function app:get-permissions ($collection as xs:string) {
    if (
        doc-available($collection || "/repo.xml") and
        exists(doc($collection || "/repo.xml")//repo:permissions)
    ) then (
        let $repo := doc($collection || "/repo.xml")//repo:permissions
        return map {
            "user":  $repo/@user/string(),
            "group":  $repo/@group/string(),
            "mode":  $repo/@mode/string()
        }
    ) else (
        config:sm()
    )
};

(:~
: Set permissions for either a collection or resource
:)
declare function app:set-permission($collection as xs:string, $resource as xs:string?, $permissions as map(*)) {
    if (exists($resource)) then (
        xs:anyURI($resource) ! (
            sm:chown(., $permissions?user),
            sm:chgrp(., $permissions?group),
            sm:chmod(., $permissions?mode)
        )
    ) else (
        xs:anyURI($collection) ! (
            sm:chown(., $permissions?user),
            sm:chgrp(., $permissions?group),
            sm:chmod(., replace($permissions?mode, "(r.)-", "$1x"))
        )
    )
};

(:~
 : Write sha
 :)
declare function app:write-sha($collection as xs:string, $git-sha as xs:string) {
    xmldb:store($collection, "gitsha.xml",
        <hash>
            <value>{ app:shorten-sha($git-sha) }</value>
        </hash>
    )
};

(:~
 : shorten commit hash in the same way as git does
 : this will ensure that gitsha.xml created from external tools are recognized
 :)
declare function app:shorten-sha($git-sha as xs:string?) as xs:string? {
    substring($git-sha, 1, 7)
};

declare function app:request-json($request as element(http:request)) {
    let $raw := app:request($request)
    let $decoded := util:base64-decode($raw[2])
    let $json := parse-json($decoded)
    
    return ($raw[1], $json)
};

(:~
 : Github request
 :)
declare function app:request($request as element(http:request)) {
    (: let $_ := util:log("info", $request/@href) :)
    let $response := http:send-request($request)
    let $status-code := xs:integer($response[1]/@status)

    return
        if ($status-code >= 400)
        then error(xs:QName("app:connection-error"), "server connection failed: " || $response[1]/@message || " (" || $status-code || ")", $response[1])
        else $response
};

(:~
 : Resolve relative file path against a base collection
 : app:file-to-resource("/db", "a/b/c") -> map { "name": "c", "collection": "/db/a/b/"}
 :
 : @param $base     the absolute DB path to a collection; no slash at the end
 : @param $filepath never begins with slash and always points to a resource
 : @return a map with name and collection
 :)
declare %private function app:file-to-resource($base as xs:string, $filepath as xs:string) as map(*) {
    let $parts := tokenize($filepath, '/')
    let $rel-path := subsequence($parts, 0, count($parts)) (: cut off last part :)
    return map {
        "name": xmldb:encode($parts[last()]),
        "collection": string-join(($base, $rel-path), "/") || "/"
    }
};

declare function app:delete-resource($config as map(*), $filepath as xs:string) as xs:boolean {
    let $resource := app:file-to-resource($config?path, $filepath)
    let $remove := xmldb:remove($resource?collection, $resource?name)
    let $remove-empty-col := 
        if (empty(xmldb:get-child-resources($resource?collection))) then (
            xmldb:remove($resource?collection)
        ) else ()

    return true()
};

(:~
 : Incremental update fetch and add files from git
 :)
declare function app:add-resource($config as map(*), $filepath as xs:string, $data as item()) as xs:boolean {
    let $resource := app:file-to-resource($config?path, $filepath)
    let $permissions := app:get-permissions($config?path)
    let $collection-check := 
        if (xmldb:collection-available($resource?collection)) then ()
        else (
            collection:create($resource?collection),
            app:set-permission($resource?collection, (), $permissions)
        )

    let $store := xmldb:store($resource?collection, $resource?name, $data)
    let $chmod := app:set-permission($resource?collection, $store, $permissions)
    return true()
};
