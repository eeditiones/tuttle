xquery version "3.1";

module namespace app="http://exist-db.org/apps/tuttle/app";
declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";

import module namespace xmldb="http://exist-db.org/xquery/xmldb";
import module namespace compression="http://exist-db.org/xquery/compression";
import module namespace repo="http://exist-db.org/xquery/repo";
import module namespace sm="http://exist-db.org/xquery/securitymanager";
import module namespace dbutil="http://exist-db.org/xquery/dbutil";

import module namespace config="http://exist-db.org/apps/tuttle/config" at "config.xql";

(:~
 : Unzip helper function
 :)
declare function app:unzip-store($path as xs:string, $data-type as xs:string, $data as item()?, $param as item()*) {
    let $archive-root := substring-before($path, '/')
    let $archive-root-length := string-length($archive-root)
    let $object := substring-after($path, '/') 

    return 
        if ($data-type = 'folder') then 
            let $mkcol := app:mkcol($param, $object)
            return
                <entry path="{$object}" data-type="{$data-type}"/>
        else 
            let $resource-path := "/" || tokenize($object, '[^/]+$')[1]
            let $resource-collection := concat($param, $resource-path)
            let $resource-filename := xmldb:encode(replace($object, $resource-path, ""))
            return
                try {
                    let $collection-check := if (xmldb:collection-available($resource-collection)) then () else app:mkcol($resource-collection)
                    let $store := xmldb:store($resource-collection, $resource-filename, $data)
                    return ()
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
 : Filter function to blacklist resources
 :)
declare function app:unzip-filter($path as xs:string, $data-type as xs:string, $param as item()*) as xs:boolean { 
    let $blacklist := config:blacklist()
    return
        if (contains($path, $blacklist)) then
            false()
        else
            true()
};

(:~
 : Move staging collection to final collection
 :)
declare function app:move-collections($collection-source as xs:string, $collection-target as xs:string, $prefix as xs:string) {
    let $fullpath-collection-source :=  $prefix || "/" || $collection-source
    let $fullpath-collection-target :=  $prefix || "/" || $collection-target

    return
        for $child in xmldb:get-child-collections($fullpath-collection-source) 
            let $fullpath-child-source := $fullpath-collection-source || "/" || $child
            let $fullpath-child-target := $fullpath-collection-target || "/" 
            return 
                xmldb:move($fullpath-child-source, $fullpath-child-target)
};

(:~
 : Move staging collection to final collection
 :)
declare function app:move-resources($collection-source as xs:string, $collection-target as xs:string, $prefix as xs:string) {
    let $fullpath-collection-source :=  $prefix || "/" || $collection-source
    let $fullpath-collection-target :=  $prefix || "/" || $collection-target
    
    return
        for $child in xmldb:get-child-resources($fullpath-collection-source) 
            return 
                xmldb:move($fullpath-collection-source, $fullpath-collection-target, $child)
};

(:~ 
 : Cleanup destination collection - delete collections from target collection
 :)
declare function app:cleanup-collection($collection as xs:string, $prefix as xs:string) {
    let $blacklist := [config:blacklist(), config:lock()]
    let $fullpath-collection :=  $prefix || "/" || $collection 

    return
        for $child in xmldb:get-child-collections($fullpath-collection)
            where not(contains($child, $blacklist))
                let $fullpath-child := $fullpath-collection || "/" || $child
                return 
                    xmldb:remove($fullpath-child)
};

(:~
 : Cleanup destination collection - delete resources from target collection
 :)
declare function app:cleanup-resources($collection as xs:string, $prefix as xs:string) {
    let $blacklist := config:blacklist()
    let $fullpath-collection :=  $prefix || "/" || $collection 

    return
        for $child in xmldb:get-child-resources($fullpath-collection)
            where not(contains($child, $blacklist))
            return 
                xmldb:remove($fullpath-collection, $child)
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
        let $collection-check := 
            if (xmldb:collection-available($collection-prefix)) then () else app:mkcol($collection-prefix)
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
    try {
        let $xml := '<task><value>'|| $task ||'</value></task>'
        return xmldb:store($collection, config:lock(), $xml)
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
 : Delete lock file
 :)
declare function app:lock-remove($collection as xs:string) {
    try {
        xmldb:remove($collection, config:lock())
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
: Set recursive permissions to whole collection 
:)
declare function app:set-permission($collection as xs:string) {
    let $collection-uri := config:prefix() || "/" || $collection

    return 
        dbutil:scan(xs:anyURI($collection-uri), function($collection-url, $resource) {
        let $path := ($resource, $collection-url)[1]
        return (
            if ($resource) then
                    app:set-permission($collection, $path, "resource")
                else
                    app:set-permission($collection, $path, "collection")
            )
        })
};

(:~
: Set permissions for $path 
: $type: 'collection' or 'resource'
:)
declare function app:set-permission($collection as xs:string, $path as xs:string, $type as xs:string) {
    let $collection-uri := config:prefix() || "/" || $collection
    let $repo := doc(concat($collection-uri, "/repo.xml"))/repo:meta/repo:permissions

    return (
        if (exists($repo)) then (
            sm:chown($path, $repo/@user/string()),
            sm:chgrp($path, $repo/@group/string()),
            if ($type = "resource") then
                    sm:chmod($path, $repo/@mode/string())
                else
                    sm:chmod($path, replace($repo/@mode/string(), "(..).(..).(..).", "$1x$2x$3x"))
        )
        else (
            sm:chown($path, config:sm()?user),
            sm:chgrp($path, config:sm()?group),
            if ($type = "resource") then
                    sm:chmod($path, config:sm()?mode)
                else
                    sm:chmod($path, replace(config:sm()?mode, "(..).(..).(..).", "$1x$2x$3x")))
        )
};

(:~
: Get Sha of production collection
:)
declare function app:production-sha($collection as xs:string) {
    let $gitsha := config:prefix() || "/" || $collection || "/gitsha.xml"

    return 
        if (doc($gitsha)/hash/value/text()) then 
            doc($gitsha)/hash/value/text()
        else
            map { 
                "message" : concat($gitsha, " not exist")
            }
};

(:~
 : Helper function of unzip:mkcol() 
:)
declare function app:mkcol-recursive($collection, $components) as xs:string* {
    if (exists($components)) then
        let $newColl := concat($collection, "/", $components[1])
        return (
            xmldb:create-collection($collection, $components[1]),
            if ($components[2]) then 
                app:mkcol-recursive($newColl, subsequence($components, 2))
            else ()
        )
    else ()
};

(:~
 : Helper function to recursively create a collection hierarchy
 :)
declare function app:mkcol($collection, $path) as xs:string* {
    app:mkcol-recursive($collection, tokenize($path, "/") ! xmldb:encode(.))
};

(:~
 : Helper function to recursively create a collection hierarchy
 :)
declare function app:mkcol($path) as xs:string* {
    app:mkcol('/db', substring-after($path, "/db/"))
};

(:~
 : Write sha
 :)
declare function app:write-sha($collection as xs:string, $git-sha as xs:string) {
    let $filename := "gitsha.xml"
    let $sha := '<hash><value>'|| substring($git-sha, 1, 6)  ||'</value></hash>'

    return xmldb:store($collection, $filename, $sha)
};