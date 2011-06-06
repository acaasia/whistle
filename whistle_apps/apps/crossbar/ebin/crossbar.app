{application,crossbar,
             [{description,"Crossbar - REST Interface to the stars"},
              {vsn,"0.3.5"},
              {modules,[accounts,api_auth,callflows,clicktocall,conferences,
                        crossbar,crossbar_app,crossbar_bindings,crossbar_doc,
                        crossbar_module_sup,crossbar_resource,
                        crossbar_session,crossbar_sup,crossbar_util,
                        crossbar_validator,devices,evtsub,media,menus,noauthn,
                        noauthz,plists,registrations,resources,servers,signup,
                        simple_authz,static_resource,t_evtsub,token_auth,
                        user_auth,users,v1_resource,vmboxes]},
              {registered,[]},
              {applications,[kernel,stdlib,crypto,mochiweb,webmachine]},
              {mod,{crossbar_app,[]}},
              {env,[]}]}.