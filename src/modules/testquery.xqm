xquery version "3.1";

import module namespace github="http://exist-db.org/apps/tuttle/github" at "github.xql";
import module namespace app="http://exist-db.org/apps/tuttle/app" at "app.xql";
import module namespace api="http://exist-db.org/apps/tuttle/api" at "api.xql";
import module namespace config="http://exist-db.org/apps/tuttle/config" at "config.xql";
import module namespace gitlab="http://exist-db.org/apps/tuttle/gitlab" at "gitlab.xql";


let $git-collection := $config:default-collection
let $config := $config:collections?($git-collection)
let $url := $config?baseurl || "/projects/" || $config?project-id ||  "/repository/commits/" || "743dd6" ||"/diff"

return $url