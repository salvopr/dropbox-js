# Represents a user accessing the application.
class DropboxClient
  # Dropbox client representing an application.
  #
  # For an optimal user experience, applications should use a single client for
  # all Dropbox interactions.
  #
  # @param {Object} options the application type and API key
  # @option {Boolean} sandbox true for applications that request sandbox access
  #     (access to a single directory exclusive to the app)
  # @option {String} key the application's API key
  # @option {String} secret the application's API secret
  # @option {String} token if set, the user's access token
  # @option {String} tokenSecret if set, the secret for the user's access token
  # @option {String} uid if set, the user's Dropbox UID
  constructor: (options) ->
    @sandbox = options.sandbox or false
    @oauth = new DropboxOauth options
    @uid = options.uid or null

    @apiServer = options.server or 'https://api.dropbox.com'
    @authServer = options.authServer or @apiServer.replace('api.', 'www.')
    @fileServer = options.fileServer or
                    @apiServer.replace('api.', 'api-content.')
    
    @setupUrls()

  # Plugs in the authentication driver.
  #
  # @param {String} url the URL that will be used for OAuth callback; the
  #     application must be able to intercept this URL and obtain the query
  #     string provided by Dropbox
  # @param {function(String, function(String))} driver the implementation of
  #     the authorization flow; the function should redirect the user to the
  #     URL received as the first argument, wait for the user to be redirected
  #     to the URL provded to authCallback, and then call the supplied function
  #     with
  authDriver: (url, driver) ->
    @authDriverUrl = url
    @authDriver = driver

  # Removes all login information.
  #
  # @return {Dropbox.Client} this, for easy call chaining
  reset: ->
    @uid = null
    @oauth.setToken null, ''
    @

  setupUrls: ->
    @urls = 
      requestToken: "#{@apiServer}/1/oauth/request_token"
      authorize: "#{@authServer}/1/oauth/authorize"
      accessToken: "#{@apiServer}/1/oauth/access_token"
      getFiles: "#{@fileServer}/1/files"
      putFiles: "#{@fileServer}/1/files_put"
      postFiles: "#{@fileServer}/1/files"
      metadata: "#{@apiServer}/1/metadata"
      delta: "#{@apiServer}/1/delta"
      revisions: "#{@apiServer}/1/revisions"
      restore: "#{@apiServer}/1/restore"
      search: "#{@apiServer}/1/search"
      shares: "#{@apiServer}/1/shares"
      media: "#{@apiServer}/1/media"
      copy_ref: "#{@apiServer}/1/copy_ref"
      thumbnails: "#{@fileServer}/1/thumbnails"
      fileOps: "#{@apiServer}/1/fileops"
      fileOpsCopy: "#{@apiServer}/1/fileops/copy"
      fileOpsCreateFolder: "#{@apiServer}/1/fileops/create_folder"
      fileOpsDelete: "#{@apiServer}/1/fileops/delete"
      fileOpsMove: "#{@apiServer}/1/fileops/move" 

  # OAuth credentials.
  #
  # @return {Object} a plain object whose properties can be passed to the
  #     Dropbox.Client constructor to reuse this client's login credentials
  credentials: ->
    value =
      key: @oauth.key
      secret: @oauth.secret
    if @oauth.token
      value.token = @oauth.token
      value.tokenSecret = @oauth.tokenSecret
      value.uid = @uid
    value
      
  # Authenticates the app's user to Dropbox' API server.
  #
  # @param {function(String, String)} callback called when the authentication
  #     completes; if successful, the first argument is the user's Dropbox
  #     user id, which is guaranteed to be consistent across API calls from the
  #     same application (not across applications, though); if an error occurs,
  #     the first argument is null and the second argument is an error string;
  #     the error is suitable for logging, but not for presenting to the user,
  #     as it is not localized
  authenticate: (callback) ->
    @requestToken (data, error) =>
      if error
        callback null, error
        return
      token = data.oauth_token
      tokenSecret = data.oauth_token_secret
      @oauth.setToken token, tokenSecret
      @authDriver @authorizeUrl(token), (url) =>
        @getAccessToken (data, error) =>
          if error
            @reset()
            callback null, error
            return
          token = data.oauth_token
          tokenSecret = data.oauth_token_secret
          @oauth.setToken token, tokenSecret
          @uid = data.uid
          callback data.uid

  # Really low-level call to /oauth/request_token
  #
  # This a low-level method called by authorize. Users should call authorize.
  #
  # @param {function(data, error)} callback called with the result to the
  #    /oauth/request_token HTTP request
  requestToken: (callback) ->
    params = @oauth.addAuthParams 'POST', @urls.requestToken, {}
    DropboxXhr.request 'POST', @urls.requestToken, params, null, callback
  
  # The URL for /oauth/authorize, embedding the user's token.
  #
  # This a low-level method called by authorize. Users should call authorize.
  #
  # @param {String} token the oauth_token obtained from an /oauth/request_token
  #     call
  # @return {String} the URL that the user's browser should be redirected to
  #     in order to perform an /oauth/authorize request
  authorizeUrl: (token) ->
    params = { oauth_token: token, oauth_callback: @authDriverUrl }
    "#{@urls.authorize}?" + DropboxXhr.urlEncode(params)

  # Exchanges an OAuth request token with an access token.
  #
  # This a low-level method called by authorize. Users should call authorize.
  #
  # @param {function(data, error)} callback called with the result to the
  #    /oauth/access_token HTTP request
  getAccessToken: (callback) ->
    params = @oauth.addAuthParams 'POST', @urls.accessToken, {}
    DropboxXhr.request 'POST', @urls.accessToken, params, null, callback

  # Downloads a file
  #
  # @param {String} root relative to which path is specified. Valid values
  #     are 'sandbox' and 'dropbox'
  # @param {String} path to the file you want to retrieve
  # @param {Number} rev of the file to retrive, defaults to the most recent
  #     revision
  # @param {function(data, error)} callback called with the result to the
  #     /files (GET) HTTP request. 
  getFiles: (root, path, rev, callback) ->
    url = "#{@urls.getFiles}/#{root}/#{path}"
    params = {}
    if rev?
        params = {rev: rev}
    authorize = @oauth.authHeader 'GET', url, params
    DropboxXhr.request 'GET', url, params, authorize, callback

  # Uploads a file using PUT semantics
  #
  # @param {String} root relative to which path is specified. Valid values
  #     are 'sandbox' and 'dropbox'
  # @param {String} path to the file you want to retrieve
  # @param {Binary} body of the file
  # @param {String} locale to which to translate the metadata returned on
  #     successful upload
  # @param {Boolean} overwrite the existing file at the path (if any)
  # @param {Number} parent_rev of the uploaded file (i.e. revision of the file
  #     being edited)
  # @param {function(data, error)} callback called with the result to the
  #     /files (GET) HTTP request. 
  putFiles: (root, path, body, locale, overwrite, parentRev, callback) ->
    url = "#{@urls.putFiles}/#{root}/#{path}"
    params = {}
    if parentRev?
        params['parent_rev'] = parentRev
    if locale?
        params['locale'] = locale
    if overwrite?
        params['overwrite'] = overwrite
    authorize = @oauth.authHeader 'PUT', url, params
    DropboxXhr.request 'PUT', url, params, authorize, callback, body

  # Post files
  # @param {String} root relative to which path is specified. Valid values
  #     are 'sandbox' and 'dropbox'
  # @param {String} path to the file you want to retrieve
  # @param {Binary} file to be uploaded
  # @param {String} locale to which to translate the metadata returned on
  #     successful upload
  # @param {Boolean} overwrite the existing file at the path (if any)
  # @param {Number} parent_rev of the uploaded file (i.e. revision of the file
  #     being edited)
  # @param {function(data, error)} callback called with the result to the
  #     /files (GET) HTTP request. 
  postFiles: (root, path, file, locale, overwrite, parent_rev, callback) ->
    url - "#{@urls.putFiles}/#{root}/#{path}"
    authorize = @oauth.authHeader 'POST', url, {}
    null

  # @param {String} root relative to which path is specified. Valid values
  #     are 'sandbox' and 'dropbox'
  # @param {String} path to the file you want to retrieve
  # @param {Number} file_limit on the number of files listed. Defaults to
  # 10,000, max is 25,000.
  # @param {String} hash field of the last call to /metadata (on this folder). If
  #     nothing has changed since the last call, the response will be a 304
  #     (not modified) status code
  # @param {Boolean} list
  # @param {Boolean} include_deleted
  # @param {Number} rev
  # @param {String} locale
  # @param {function(data, error)} callback called with the result to the
  #     /files (GET) HTTP request. 
  metadata: (root, path, fileLimit, hash, list, includeDeleted, rev, locale, callback) ->
    url = "#{@urls.metadata}/#{root}/#{path}"  
    params = {}
    if fileLimit?
        params['file_limit'] = fileLimit
    if hash?
        params['hash'] = hash
    if list?
        params['list'] = list
    if includeDeleted?
        params['include_deleted'] = includeDeleted
    if rev?
        params['rev'] = rev
    if locale?
        params['locale'] = locale
    authorize = @oauth.authHeader 'GET', url, params
    DropboxXhr.request 'GET', url, params, authorize, callback

  # @param {function(data, error)} callback called with the result to the
  #     /files (GET) HTTP request. 
  delta: (cursor, locale, callback) ->
    null

  # @param {String} root relative to which path is specified. Valid values
  #     are 'sandbox' and 'dropbox'
  # @param {String} path to the file you want to retrieve
  # @param {function(data, error)} callback called with the result to the
  #     /files (GET) HTTP request. 
  revisions: (root, path, rev_limit, locale, callback) ->
    null


  # @param {String} root relative to which path is specified. Valid values
  #     are 'sandbox' and 'dropbox'
  # @param {String} path to the file you want to retrieve
  # @param {function(data, error)} callback called with the result to the
  #     /files (GET) HTTP request. 
  restore: (root, path, rev, locale, callback) ->
    null

  # @param {String} root relative to which path is specified. Valid values
  #     are 'sandbox' and 'dropbox'
  # @param {String} path to the file you want to retrieve
  # @param {function(data, error)} callback called with the result to the
  #     /files (GET) HTTP request. 
  search: (root, path, query, file_limit, include_deleted, locale, callback) ->
    null

  # @param {String} root relative to which path is specified. Valid values
  #     are 'sandbox' and 'dropbox'
  # @param {String} path to the file you want to retrieve
  # @param {function(data, error)} callback called with the result to the
  #     /files (GET) HTTP request. 
  shares: (root, path, locale, short_url, callback) ->
    null

  # @param {String} root relative to which path is specified. Valid values
  #     are 'sandbox' and 'dropbox'
  # @param {String} path to the file you want to retrieve
  # @param {function(data, error)} callback called with the result to the
  #     /files (GET) HTTP request. 
  media: (root, path, locale, callback) ->
    null
  # @param {String} root relative to which path is specified. Valid values
  #     are 'sandbox' and 'dropbox'
  # @param {String} path to the file you want to retrieve
  # @param {function(data, error)} callback called with the result to the
  #     /files (GET) HTTP request. 
  copy_ref: (root, path, callback) ->
    null

  # @param {String} root relative to which path is specified. Valid values
  #     are 'sandbox' and 'dropbox'
  # @param {String} path to the file you want to retrieve
  # @param {function(data, error)} callback called with the result to the
  #     /files (GET) HTTP request. 
  thumbnails: (eoot, path, format, size, callback) ->
    null

  # @param {String} root relative to which path is specified. Valid values
  #     are 'sandbox' and 'dropbox'
  # @param {String} path to the file you want to retrieve
  # @param {Number} rev of the file to retrive, defaults to the most recent
  #     revision
  # @param {function(data, error)} callback called with the result to the
  #     /files (GET) HTTP request. 
  fileops_copy: (root, from_path, to_path, locale, from_copy_ref, callback) ->
    null

  # @param {String} root relative to which path is specified. Valid values
  #     are 'sandbox' and 'dropbox'
  # @param {String} path to the file you want to retrieve
  # @param {function(data, error)} callback called with the result to the
  #     /files (GET) HTTP request. 
  fileops_create_folder: (root, path, locale, callback) ->
    null

  # @param {String} root relative to which path is specified. Valid values
  #     are 'sandbox' and 'dropbox'
  # @param {String} path to the file you want to retrieve
  # @param {function(data, error)} callback called with the result to the
  #     /files (GET) HTTP request. 
  fileops_delete: (root, path, locale, callback) ->
    null

  # @param {String} root relative to which path is specified. Valid values
  #     are 'sandbox' and 'dropbox'
  # @param {String} path to the file you want to retrieve
  # @param {function(data, error)} callback called with the result to the
  #     /files (GET) HTTP request. 
  fileops_move: (root, from_path, to_path, locale, callback) ->
    null
