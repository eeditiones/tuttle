xquery version "3.1";

module namespace gitlab="http://exist-db.org/apps/tuttle/gitlab";

import module namespace app="http://exist-db.org/apps/tuttle/app" at "app.xql";
import module namespace config="http://exist-db.org/apps/tuttle/config" at "config.xql";

declare namespace http="http://expath.org/ns/http-client";

declare function gitlab:repo-url($config as map(*)) as xs:string {
    $config?baseurl || string-join(
        ("projects", $config?project-id, "repository"), "/")
};

declare function gitlab:commit-ref-url($config as map(*)) as xs:string {
    gitlab:repo-url($config) || "/commits/?ref_name=" || $config?ref 
};

(:~
 : clone defines Version repo 
 :)
declare function gitlab:clone($config as map(*), $collection as xs:string, $sha as xs:string) {
    try {
        let $zip := gitlab:request(
            gitlab:repo-url($config) || "/archive.zip?sha=" || $sha, $config?token)

        let $delete-collection :=
            if (xmldb:collection-available($collection))
            then xmldb:remove($collection)
            else ()

        let $create-collection := xmldb:create-collection("/", $collection)

        let $write-sha := app:write-sha($collection,
            if (exists($sha)) then $sha else gitlab:get-last-commit($config)?sha)

        let $clone := app:extract-archive($zip, $collection)

        return  map { "message" : "success" }
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
 : Get the last commit
 :)
declare function gitlab:get-last-commit($config as map(*)) {
    let $url := gitlab:commit-ref-url($config)
    let $request := gitlab:request-json($url, $config?token)

    return
        map { 
            "sha" : app:shorten-sha($request?1?short_id)
        }
};

(:~
 : Get all commits
 :)
declare function gitlab:get-commits($config as map(*)) as array(*)* {
    gitlab:get-commits($config, ())
};

(:~
 : Get N commits
 :)
declare function gitlab:get-commits($config as map(*), $count as xs:integer?) as array(*)* {
    let $url := gitlab:commit-ref-url($config)
    let $json := gitlab:request-json($url, $config?token)

    let $commits :=
        if (empty($json))                    (: raise error here? returns zero commits :)
        then []
        else if (empty($count))
        then $json
        else if ($count > array:size($json)) (: raise error here? returns everything :)
        then $json
        else if ($count < 0)                 (: raise error here? returns zero commits :)
        then []
        else array:subarray($json, 1, $count)

    return
        array:for-each($commits, function($commit-info as map(*)) as array(*) {
            [
                app:shorten-sha($commit-info?short_id),
                $commit-info?message
            ]
        })
};

(:~ 
 : Get diff between production collection and gitlab-newest
 :)
declare function gitlab:get-newest-commits($config as map(*), $collection as xs:string) {
    let $prod-sha := app:production-sha($collection)
    let $commits-all := gitlab:get-commits($config)?1
    let $how-many := index-of($commits-all, $prod-sha) - 1

    return subsequence($commits-all, 1, $how-many)
};

(:~ 
 : Check if sha exist
 :)
declare function gitlab:available-sha($config as map(*), $sha as xs:string) as xs:boolean {
    $sha = gitlab:get-commits($config)
};

(:~ 
 : Get files removed and added from commit 
 :)
declare function gitlab:get-commit-files($config as map(*), $sha as xs:string) as array(*) {
    let $url := gitlab:repo-url($config) || "/commits/" || $sha ||"/diff" 
    let $response := gitlab:request-json($url, $config?token)

    let $changes :=
        array:for-each($response, function ($change) {
            if ($change?new_file) then
                map { "new" : $change?new_path }
            else if ($change?renamed_file) then
                map {  
                    "del" : $change?old_path,
                    "new" : $change?new_path
                }
            else if ($change?deleted_file) then
                map { "del" : $change?new_path }
            else if ( $change?new_path = $change?old_path ) then
                map { "new" : $change?new_path }
            else ()
        }) 

    return map{
        'del': $changes?*?del,
        'new': $changes?*?new
    }
};

(:~
 : Get blob of a file
 :)
declare function gitlab:get-blob($config as map(*), $filename as xs:string, $sha as xs:string) {
    let $file := escape-html-uri(replace($filename,"/", "%2f"))
    let $url-blob-id := gitlab:repo-url($config) || "/files/" || $file || "?ref=" || $sha
    let $blob-id := gitlab:request-json($url-blob-id, $config?token)?blob_id

    let $url-blob := gitlab:repo-url($config) || "/blobs/" || $blob-id || "/raw"
    return gitlab:request($url-blob, $config?token)
};

(:~
 : Get HTTP-URL
 :)
declare function gitlab:get-url($config as map(*)) {
    let $info := gitlab:request-json($config?baseurl || "/projects/" || $config?project-id, $config?token)
    
    return $info?http_url_to_repo
};

(:~ 
 : Run incremental update on collection
 :)
declare function gitlab:incremental($config as map(*), $collection as xs:string){
    for $sha in reverse(gitlab:get-newest-commits($config, $collection))
    let $del := gitlab:incremental-delete($config, $collection, $sha)
    let $add := gitlab:incremental-add($config, $collection, $sha)
    let $writesha := app:write-sha($config?path, $sha)
    return ($del, $add) 
};

(:~ 
 : Run incremental update on collection in dry mode
 :) 

declare function gitlab:incremental-dry($config as map(*), $collection as xs:string){
    let $changes :=
        for $sha in reverse(gitlab:get-newest-commits($config, $collection))
        return gitlab:get-commit-files($config, $sha)

    return map {
        'del': $changes?del,
        'new': $changes?new
    }
};

declare function gitlab:check-signature ($collection as xs:string, $apikey as xs:string) as xs:string {
    request:get-header("X-Gitlab-Token") = $apikey
};

(:~ 
 : Incremental updates delete files
 :)
declare %private function gitlab:incremental-delete($config as map(*), $collection as xs:string, $sha as xs:string){
    for $resource in gitlab:get-commit-files($config, $sha)?del
    let $resource-path := tokenize($resource, '[^/]+$')[1]
    let $resource-collection := $config?path || "/" || $resource-path
    let $resource-filename := xmldb:encode(replace($resource, $resource-path, ""))

    return 
        try {
            let $remove := xmldb:remove($resource-collection, $resource-filename)
            let $remove-empty-col := 
                if (empty(xmldb:get-child-resources($resource-collection)))
                then xmldb:remove($resource-collection)
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
declare %private function gitlab:incremental-add($config as map(*), $collection as xs:string, $sha as xs:string){
    for $resource in gitlab:get-commit-files($config, $sha)?new
    let $resource-path := tokenize($resource, '[^/]+$')[1]
    let $resource-collection := config:prefix() || "/" || $collection || "/" || $resource-path
    let $resource-filename := 
        if ($resource-path = "") then
            xmldb:encode($resource)
        else
            xmldb:encode(replace($resource, $resource-path, ""))
    let $resource-fullpath := $resource-collection || $resource-filename

    return 
        try {
            let $data := gitlab:get-blob($config, $resource, $sha)
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
 : Gitlab request
 :)

declare %private function gitlab:request-json($url as xs:string, $token as xs:string?) as element(http:request) {
    app:request-json(gitlab:build-request($url, $token))
};

declare %private function gitlab:request($url as xs:string, $token as xs:string?) {
    app:request(gitlab:build-request($url, $token))
};

declare %private function gitlab:build-request($url as xs:string, $token as xs:string) as element(http:request) {
    <http:request http-version="1.1" href="{$url}" method="get">
        {
            if (empty($token) or $token = "")
            then ()
            else <http:header name="PRIVATE-TOKEN" value="{$token}"/>
        }
    </http:request>
};
