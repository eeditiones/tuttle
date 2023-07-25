xquery version "3.1";

module namespace config="http://exist-db.org/apps/tuttle/config";

(:~
 : Configurtion file
 :)
declare variable $config:tuttle-config := doc("/db/apps/tuttle/data/tuttle.xml")/tuttle;

(:~
 : Git configuration
 :)
declare function config:collections($collection as xs:string){
    let $config := $config:tuttle-config/repos
    let $colllection-env := replace($collection, "-", "_")
    let $token-env := concat("tuttle_token_", $colllection-env)

    let $specific := if ($config/collection[@name = $collection]/type/string() = "github") then (
        map {
            "repo" : $config/collection[@name = $collection]/repo/string(),
            "owner" : $config/collection[@name = $collection]/owner/string()
        }
    )
    else (
       map {
            "project-id" : $config/collection[@name = $collection]/project-id/string()
        }
    )
    return map:merge (($specific ,map {
        "vcs" : $config/collection[@name = $collection]/type/string(),
        "baseurl" : $config/collection[@name = $collection]/baseurl/string(),
        "ref" : $config/collection[@name = $collection]/ref/string(),
        "token" : if (environment-variable($token-env) != "") then
                        environment-variable($token-env)
                    else
                        $config/collection[@name = $collection]/token/string(),
        "hookuser" :  $config/collection[@name = $collection]/hookuser/string(),
        "hookpasswd" : $config/collection[@name = $collection]/hookpasswd/string()
    }))
};

(:~
 : List collection names
 :)
declare function config:list-collections() {
    $config:tuttle-config/repos/collection/@name/string()
};


(:~
 : Defile default collection
 :)
declare function config:default-collection(){
    $config:tuttle-config/repos/collection[default="true"]/@name/string()
};

(:~
 : Blacklist - these files are not checkout from git and are ignored
 :)
declare function config:blacklist(){
    $config:tuttle-config/blacklist/file/string()
};

(:~
 : Suffix of the checked out git statging collection 
 :)
declare function config:suffix(){
    $config:tuttle-config/config/@suffix/string()
};

(:~
 : The running task is stored in the lockfile. It ensures that two tasks do not run at the same time. 
 :)
declare function config:lock(){
    $config:tuttle-config/config/@lock/string()
};

(:~
 : Prefix for collections
 :)
declare function config:prefix(){
    $config:tuttle-config/config/@prefix/string()
};

(:~
 : The destination where the key for the webhook is stored.
 :)
declare function config:apikeys(){
    $config:tuttle-config/config/@apikeys/string()
};

(:~
 : DB User and Permissions as fallback if "permissions" not set in repo.xml
 :)
declare function config:sm(){
    let $sm := $config:tuttle-config/config/sm

    return map {
        "user" : $sm/@user/string(),
        "group" : $sm/@group/string(),
        "mode" : $sm/@mode/string()
    }
};
