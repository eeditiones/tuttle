xquery version "3.1";

module namespace gitlab="http://exist-db.org/apps/tuttle/gitlab";

import module namespace http="http://expath.org/ns/http-client";
import module namespace compression="http://exist-db.org/xquery/compression";

import module namespace app="http://exist-db.org/apps/tuttle/app" at "app.xql";
import module namespace config="http://exist-db.org/apps/tuttle/config" at "config.xql";


(:~
 : clone defines Version repo 
 :)
declare function gitlab:clone($config as map(*), $collection as xs:string, $sha as xs:string) {
    let $url := $config?baseurl || "/projects/" || $config?project-id ||  "/repository/archive.zip?sha=" || $sha

    return
        try {
            if (gitlab:request($url, $config?token)[1]/xs:integer(@status) ne 200) then (
                map {
                    "message" : concat($config?vcs, " error: ", gitlab:request($url, $config?token)[1]/xs:string(@message))
                    } )
            else (
                if (gitlab:available-sha($config, $sha)) then (
                    let $request := gitlab:request($url, $config?token)
                    let $filter := app:unzip-filter#3
                    let $unzip-action := app:unzip-store#4
                    let $filter-params := () 
                    let $data-params := ($collection)         
                    let $delete-collection :=
                        if(xmldb:collection-available($collection)) then 
                            xmldb:remove($collection)
                        else ()
                    let $create-collection := xmldb:create-collection("/", $collection)
                    let $wirte-sha := app:write-sha($collection,$sha)
                    let $clone := compression:unzip ($request[2], $filter, $filter-params,  $unzip-action, $data-params)
                    return  map {
                            "message" : "Success"
                    }
                ) 
                else (
                    map {
                        "message" : "REF not exist"
                    } 
                )
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
 : Get files removed and added from commit 
 :)
declare function gitlab:get-commit-files($config as map(*), $sha as xs:string) {
    let $url := $config?baseurl || "/projects/" || $config?project-id ||  "/repository/commits/" || $sha ||"/diff" 

    return 
        if (gitlab:request($url, $config?token)[1]/xs:integer(@status) ne 200) then (
            map {
                "message" : concat($config?vcs, " error: ", gitlab:request($url, $config?token)[1]/xs:string(@message))
            } )
        else (
            let $request :=
                parse-json(util:base64-decode(gitlab:request($url, $config?token)[2]))
            let $changes := for $size in 1 to array:size($request) 
                return
                    if ($request($size)?new_file) then
                        map { "new" :  $request($size)?new_path}
                    else if ($request($size)?renamed_file) then
                        map {  
                            "del" : $request($size)?old_path, 
                            "new" : $request($size)?new_path}
                    else if ($request($size)?deleted_file) then
                        map { "del" : $request($size)?new_path}
                    else if ( $request($size)?new_path = $request($size)?old_path ) then
                        map { "new" :  $request($size)?new_path}
                    else ()
            return map:merge(( (map:entry('del', $changes?del), map:entry('new', $changes?new))))
        )
};

(:~
 : Get the last commit
 :)
declare function gitlab:get-lastcommit-sha($config as map(*)) {
    let $url := $config?baseurl || "/projects/" || $config?project-id || "/repository/commits/?ref_name=" || $config?ref 
    let $request :=
        parse-json(util:base64-decode(gitlab:request($url, $config?token)[2]))
            
    return
        map { 
            "sha" : substring($request?1?short_id, 1, 6)
        }
};

(:~
 : Get all commits
 :)
declare function gitlab:get-commits($config as map(*)) {
    let $url := $config?baseurl || "/projects/" || $config?project-id || "/repository/commits/?ref_name=" || $config?ref  
    
    return
        if (gitlab:request($url, $config?token)[1]/xs:integer(@status) ne 200) then (
            map {
                "message" : concat($config?vcs, " error: ", gitlab:request($url, $config?token)[1]/xs:string(@message))
                } )
        else (
            let $request :=
                parse-json(util:base64-decode(gitlab:request($url, $config?token)[2]))
            for $size in 1 to array:size($request)
                return  
                    [substring(array:get($request, $size)?short_id, 1, 6) , array:get($request, $size)?message]
        )
};

(:~
 : Get N commits
 :)
declare function gitlab:get-commits($config as map(*), $count as xs:int) {
    let $url := $config?baseurl || "/projects/" || $config?project-id || "/repository/commits/?ref_name=" || $config?ref
    
    return
        if (gitlab:request($url, $config?token)[1]/xs:integer(@status) ne 200) then (
            map {
                "message" : concat($config?vcs, " error: ", gitlab:request($url, $config?token)[1]/xs:string(@message))
                } )
        else (
            let $request :=
                parse-json(util:base64-decode(gitlab:request($url, $config?token)[2]))
            let $count-checked := if ($count > array:size($request) ) then array:size($request) else $count
            for $size in 1 to $count-checked
                return  
                    [substring(array:get($request, $size)?short_id, 1, 6) , array:get($request, $size)?message]
        )

};

(:~ 
 : Check if sha exist
 :)
declare function gitlab:available-sha($config as map(*), $sha as xs:string) as xs:boolean {
    if (contains($sha,gitlab:get-commits($config))) then
        true()
    else
        false()
};

(:~ 
 : Get diff between production collection and gitlab-newest
 :)
declare function gitlab:get-newest-commits($config as map(*), $collection as xs:string) {
    let $prod-sha := app:production-sha($collection)
    let $commits-all := gitlab:get-commits($config)?1
    let $commits-no := (xs:int(index-of($commits-all, $prod-sha)))-1

    return subsequence($commits-all, 1, $commits-no)
};

(:~
 : Get blob of a file
 :)
declare function gitlab:get-blob($config as map(*), $filename as xs:string, $sha as xs:string) {
    let $file := escape-html-uri(replace($filename,"/", "%2f"))
    let $url-blob-id := 
        $config?baseurl || "/projects/" || $config?project-id ||  "/repository/files/" || $file || "?ref=" || $sha

    return 
        if (gitlab:request($url-blob-id, $config?token)[1]/xs:integer(@status) ne 200) then (
            map {
                "message" : concat($config?vcs, " error: ", gitlab:request($url-blob-id, $config?token)[1]/xs:string(@message))
            }
        )
        else (
            let $request-blob-id := 
                parse-json(util:base64-decode(gitlab:request($url-blob-id, $config?token)[2]))?blob_id
            let $url-blob := 
                $config?baseurl || "/projects/" || $config?project-id || "/repository/blobs/" || $request-blob-id || "/raw"
            let $request-blob := gitlab:request($url-blob, $config?token)[2]
            
            return $request-blob
        )
};

(:~
 : Get HTTP-URL
 :)
declare function gitlab:get-url($config as map(*)) {
    let $url := 
        $config?baseurl ||  "/projects/" || $config?project-id
    let $request := gitlab:request($url, $config?token)
    
    return 
        if ($request[1]/xs:integer(@status) ne 200) then (
            map {
                "message" :  $request[1]/xs:string(@message)
            }
        )
        else (
            parse-json(util:base64-decode($request[2]))?http_url_to_repo
        )
};

(:~ 
 : Run incremental update on collection
 :)
declare function gitlab:incremental($config as map(*), $collection as xs:string){
    let $config := $config:collections?($collection)
    let $collection-path := $config:prefix || "/" || $collection

    return
    for $sha in reverse(gitlab:get-newest-commits($config, $collection))
        let $del := gitlab:incremental-delete($config, $collection, $sha)
        let $add := gitlab:incremental-add($config, $collection, $sha)
        let $writesha := app:write-sha($collection-path, $sha)
        return ($del, $add) 
};

(:~ 
 : Incremental updates delete files
 :)
declare %private function gitlab:incremental-delete($config as map(*), $collection as xs:string, $sha as xs:string){
    for $resource in gitlab:get-commit-files($config, $sha)?del
        let $resource-path := tokenize($resource, '[^/]+$')[1]
        let $resource-collection := $config:prefix || "/" || $collection || "/" || $resource-path
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
declare %private function gitlab:incremental-add($config as map(*), $collection as xs:string, $sha as xs:string){
    for $resource in gitlab:get-commit-files($config, $sha)?new
        let $resource-path := tokenize($resource, '[^/]+$')[1]
        let $resource-collection := $config:prefix || "/" || $collection || "/" || $resource-path
        let $resource-filename := 
            if ($resource-path= "") then
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
declare %private function gitlab:request($url as xs:string, $token as xs:string) {
    let $request := http:send-request(<http:request http-version="1.1" href="{xs:anyURI($url)}" method="get">
                                        <http:header name="PRIVATE-TOKEN" value="{$token}"/>
                                        </http:request>)
    return 
        try {
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