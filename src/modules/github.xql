xquery version "3.1";

module namespace github="http://exist-db.org/apps/tuttle/github";

import module namespace http="http://expath.org/ns/http-client";
import module namespace compression="http://exist-db.org/xquery/compression";
import module namespace crypto="http://expath.org/ns/crypto";

import module namespace app="http://exist-db.org/apps/tuttle/app" at "app.xql";
import module namespace config="http://exist-db.org/apps/tuttle/config" at "config.xql";



(:~
 : Clone defines Version repo
 :)
declare function github:clone($config as map(*), $collection as xs:string, $sha as xs:string) {
    let $url := $config?baseurl || "/repos/" || $config?owner ||  "/" || $config?repo || "/zipball/" || $sha 

    return
        try {
            if (github:request($url, $config?token)[1]/xs:integer(@status) ne 200) then (
                map {
                    "message" : concat($config?vcs, " error: ", github:request($url, $config?token)[1]/xs:string(@message))
                    } )
            else (
                    let $request := github:request($url, $config?token)
                    let $filter := app:unzip-filter#3
                    let $unzip-action := app:unzip-store#4
                    let $filter-params := ()
                    let $data-params := ($collection)
                    let $delete-collection :=
                        if(xmldb:collection-available($collection)) then
                            xmldb:remove($collection)
                        else ()
                    let $create-collection := xmldb:create-collection("/", $collection)
                let $write-sha := app:write-sha($collection, github:get-lastcommit-sha($config)?sha)

                    let $clone := compression:unzip ($request[2], $filter, $filter-params,  $unzip-action, $data-params)
                    return  map {
                            "message" : "success"
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
};

(:~
 : Get the last commit
 :)
declare function github:get-lastcommit-sha($config as map(*)) {
    let $url := $config?baseurl || "/repos/" || $config?owner || "/" || $config?repo || "/commits?sha=" || $config?ref
    let $request :=
        parse-json(util:base64-decode(github:request($url, $config?token)[2]))
    
    return map {
            "sha" : substring($request?1?sha, 1, 6)
    }
};

(:~
 : Get all commits
 :)
declare function github:get-commits($config as map(*)) {
    let $url := $config?baseurl || "/repos/" || $config?owner || "/" || $config?repo || "/commits?sha=" || $config?ref
    let $request :=
        parse-json(util:base64-decode(github:request($url, $config?token)[2]))
    
     for $size in 1 to array:size($request)
        return
            [substring(array:get($request, $size)?sha, 1, 6) , array:get($request, $size)?commit?message]
};

(:~
 : Get N commits
 :)
declare function github:get-commits($config as map(*), $count as xs:int) {
    let $url := $config?baseurl || "/repos/" || $config?owner || "/" || $config?repo || "/commits?sha=" || $config?ref
    let $request :=
        parse-json(util:base64-decode(github:request($url, $config?token)[2]))
    let $count-checked := if ($count > array:size($request) ) then array:size($request) else $count

     for $size in 1 to $count-checked
        return
            [substring(array:get($request, $size)?sha, 1, 6) , array:get($request, $size)?commit?message]
};

(:~
 : Get all commits in full sha lenght
 :)
declare function github:get-commits-fullsha($config as map(*)) {
    let $url := $config?baseurl || "/repos/" || $config?owner ||  "/" || $config?repo || "/commits?sha=" || $config?ref
    let $request :=
        parse-json(util:base64-decode(github:request($url, $config?token)[2]))
    
     for $size in 1 to array:size($request)
        return
            array:get($request, $size)?sha
};

(:~ 
 : Get diff between production collection and github-newest
 :)
declare function github:get-newest-commits($config as map(*), $collection as xs:string) {
    let $prod-sha := app:production-sha($collection)
    let $commits-all := github:get-commits($config)?1
    let $commits-all-raw := github:get-commits-fullsha($config)
    let $commits-no := (xs:int(index-of($commits-all, $prod-sha)))-1

    return subsequence($commits-all-raw, 1, $commits-no)
};

(:~
 : Check if sha exist
 :)
declare function github:available-sha($config as map(*), $sha as xs:string) as xs:boolean {
    if (contains($sha,github:get-commits($config))) then
        true()
    else
        false()
};

(:~ 
 : Run incremental update on collection
 :) 
declare function github:incremental($config as map(*), $collection as xs:string){
    let $config := config:collections($collection)
    let $collection-path := config:prefix() || "/" || $collection

    return
    for $sha in reverse(github:get-newest-commits($config, $collection))
        let $del := github:incremental-delete($config, $collection, $sha)
        let $add := github:incremental-add($config, $collection, $sha)
        let $writesha := app:write-sha($collection-path, $sha)
        return ($del, $add) 
};

(:~ 
 : Get files removed and added from commit 
 :)
declare function github:get-commit-files($config as map(*), $sha as xs:string) {
    let $url := $config?baseurl  || "/repos/" || $config?owner ||  "/" || $config?repo || "/commits/"  || $sha

    return
        if (github:request($url, $config?token)[1]/xs:integer(@status) ne 200) then (
            map {
                "message" : concat($config?vcs, " error: ", github:request($url, $config?token)[1]/xs:string(@message))
            } )
        else (
            let $request :=
                parse-json(util:base64-decode(github:request($url, $config?token)[2]))?files
            let $changes := for $size in 1 to array:size($request) 
                return
                    if ($request($size)?status eq "added") then
                        map { "new" :  $request($size)?filename}
                    else if ($request($size)?status eq "modified") then
                        map { "new" :  $request($size)?filename}
                    else if ($request($size)?status eq "renamed") then
                        map {  
                            "del" : $request($size)?previous_filename, 
                            "new" : $request($size)?filename}
                    else if ($request($size)?status eq "removed" ) then
                        map { "del" : $request($size)?filename}
                    else ()
            return map:merge(( (map:entry('del', $changes?del), map:entry('new', $changes?new))))
        )
};

(:~
 : Get blob of a file
 :)
declare function github:get-blob($config as map(*), $filename as xs:string, $sha as xs:string) {
    let $file := escape-html-uri($filename)
    let $url-blob := 
        $config?baseurl ||  "/repos/" || $config?owner ||  "/" || $config?repo || "/contents/" || $file || "?ref=" || $sha
    let $request := github:request($url-blob, $config?token)
    
    return 
        if ($request[1]/xs:integer(@status) ne 200) then (
            map {
                "message" : concat($config?vcs, " error: ", $request[1]/xs:string(@message))
            }
        )
        else (
            let $request-blob := util:base64-decode(parse-json(util:base64-decode($request[2]))?content)
            return $request-blob
        )
};

(:~
 : Get HTTP-URL
 :)
declare function github:get-url($config as map(*)) {
    let $url := 
        $config?baseurl ||  "/repos/" || $config?owner ||  "/" || $config?repo 
    let $request := github:request($url, $config?token)
    
    return 
        if ($request[1]/xs:integer(@status) ne 200) then (
            map {
                "message" :  $request[1]/xs:string(@message)
            }
        )
        else (
            parse-json(util:base64-decode($request[2]))?html_url
        )
};

(:~ 
 : Check signature for Webhook
 :)
declare function github:check-signature($collection as xs:string, $signature as xs:string, $payload  as xs:string) as xs:boolean {
    let $private-key := xs:string(doc(config:apikeys())//apikeys/collection[name = $collection]/key/text())
    let $expected-signature := "sha256="||crypto:hmac($payload, $private-key, "HmacSha256", "hex")
(:    let $expected-signature := "":)

    return 
        if ($signature = $expected-signature) then 
            true()
        else
            false()
};

(:~ 
 : Incremental updates delete files
 :)
declare %private function github:incremental-delete($config as map(*), $collection as xs:string, $sha as xs:string){
    for $resource in github:get-commit-files($config, $sha)?del
        let $resource-path := tokenize($resource, '[^/]+$')[1]
        let $resource-collection := config:prefix() || "/" || $collection || "/" || $resource-path
        let $resource-filename := xmldb:encode(replace($resource, $resource-path, ""))

        return 
            try {
                let $remove := xmldb:remove($resource-collection, $resource-filename)
                let $remove-empty-col := 
                    if (empty(xmldb:get-child-resources($resource-collection))) then
                        xmldb:remove($resource-collection)
                        else ()
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
 : Incremental update fetch and add files from git
 :)
declare %private function github:incremental-add($config as map(*), $collection as xs:string, $sha as xs:string){
    for $resource in github:get-commit-files($config, $sha)?new
        let $resource-path := tokenize($resource, '[^/]+$')[1]
        let $resource-collection := config:prefix() || "/" || $collection || "/" || $resource-path
        let $resource-filename :=
            if ($resource-path= "") then
                xmldb:encode($resource)
            else
                xmldb:encode(replace($resource, $resource-path, ""))
        let $resource-fullpath := $resource-collection || $resource-filename

        return 
            try {
                let $data := github:get-blob($config, $resource, $sha)
                let $collection-check := 
                    if (xmldb:collection-available($resource-collection)) then ()
                        else (
                            app:mkcol($resource-collection),
                            app:set-permission($collection, $resource-collection, "collection"))
                let $store := xmldb:store($resource-collection, $resource-filename, $data)
                let $chmod := app:set-permission($collection, $resource-fullpath, "resource")
                return ()
            }
            catch * {
                    map {
                        "_error": map {
                        "code": $err:code, "description": $err:description, "value": $err:value, 
                        "line": $err:line-number, "column": $err:column-number, "module": $err:module, "sha": $sha, "resource": $resource
                    }
                }
            }
};

(:~
 : Github request
 :)
declare %private function github:request($url as xs:string, $token as xs:string) {
    let $request := http:send-request(<http:request http-version="1.1" href="{xs:anyURI($url)}" method="get">
                                        <http:header name="Accept" value="application/vnd.github.v3+json" />
                                        <http:header name="Authorization" value="{concat('token ',$token)}"/>
                                        </http:request>)

    return try {
        $request
    }
    catch * {
        map {
            "_error": map {
                "code": $err:code, "description": $err:description, "value": $err:value, 
                "line": $err:line-number, "column": $err:column-number, "module": $err:module
            },
            "_request": $request?status
        }
    }
};