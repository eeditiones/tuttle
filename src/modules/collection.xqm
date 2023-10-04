xquery version '3.1';

module namespace collection="http://existsolutions.com/modules/collection";

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
