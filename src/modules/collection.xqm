xquery version '3.1';

module namespace collection="http://existsolutions.com/modules/collection";

import module namespace sm="http://exist-db.org/xquery/securitymanager";
import module namespace xmldb="http://exist-db.org/xquery/xmldb";

(:~
 : create arbitrarily deep-nested sub-collection
 : @param   $new-collection absolute path that starts with "/db"
 :          the string can have a slash at the end
 : @returns map(*) with xs:boolean success, xs:string path and xs:string error,
 :          if something went wrong error contains the description and path is
 :          the collection where the error occurred
~:)
declare
function collection:create ($path as xs:string) as map(*) {
    if (not(starts-with($path, '/db')))
    then (
        map {
            'success': false(),
            'path': $path,
            'error': 'New collection must start with /db'
        }
    )
    else (
        fold-left(
            tail(tokenize($path, '/')),
            map { 'success': true(), 'path': '' },
            collection:fold-collections#2
        )
    )
};

declare
    %private
function collection:fold-collections ($result as map(*), $next as xs:string*) as map(*) {
    let $path := concat($result?path, '/', $next)

    return
        if (not($result?success))
        then ($result)
        else if (xmldb:collection-available($path))
        then (map { 'success': true(), 'path': $path })
        else (
            try {
                map {
                    'success': exists(xmldb:create-collection($result?path, $next)),
                    'path': $path
                }
            }
            catch * {
                map {
                    'success': false(),
                    'path': $path,
                    'error': $err:description
                }
            }
        )
};

declare function collection:remove($path as xs:string, $force as xs:boolean) {
    if (not(xmldb:collection-available($path)))
    then true()
    else if ($force) 
    then xmldb:remove($path)
    else if (not(empty((
        xmldb:get-child-resources($path),
        xmldb:get-child-collections($path)
    ))))
    then error(xs:QName("collection:not-empty"), "Collection '" || $path || "' is not empty and $force is false().")
    else xmldb:remove($path)
};

(:~ 
 : Scan a collection tree recursively starting at $root. Call the supplied function once for each
 : resource encountered. The first parameter to $func is the collection URI, the second the resource
 : path (including the collection part).
 :)
declare function collection:scan($root as xs:string, $func as function(xs:string, xs:string?) as item()*) {
    collection:scan-collection($root, $func)
};

(:~ Scan a collection tree recursively starting at $root. Call $func once for each collection found :)
declare %private function collection:scan-collection($collection as xs:string, $func as function(xs:string, xs:string?) as item()*) {
    $func($collection, ()),
    collection:scan-resources($collection, $func),
    for $child-collection in xmldb:get-child-collections($collection)
    let $path := concat($collection, "/", $child-collection)
    return
        if (sm:has-access(xs:anyURI($path), "rx")) then (
            collection:scan-collection($path, $func)
        ) else ()
};

(:~
 : List all resources contained in a collection and call the supplied function once for each
 : resource with the complete path to the resource as parameter.
 :)
declare %private function collection:scan-resources($collection as xs:string, $func as function(xs:string, xs:string?) as item()*) {
    for $child-resource in xmldb:get-child-resources($collection)
    let $path := concat($collection, "/", $child-resource)
    return
        if (sm:has-access(xs:anyURI($path), "r")) then (
            $func($collection, $path)
        ) else ()
};
