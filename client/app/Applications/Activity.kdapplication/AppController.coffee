class ActivityAppController extends AppController

  KD.registerAppClass @,
    name         : "Activity"
    route        : "Activity"
    hiddenHandle : yes

  activityTypes = [
      'CStatusActivity'
      'CCodeSnipActivity'
      'CFollowerBucketActivity'
      'CNewMemberBucketActivity'
      'CDiscussionActivity'
      'CTutorialActivity'
      'CInstallerBucketActivity'
      'CBlogPostActivity'
    ]

  lastTo    = null
  lastFrom  = null
  aRange    = 2*60*60*1000
  isLoading = no

  @clearQuotes = clearQuotes = (activities)->

    return activities = for activityId, activity of activities
      activity.snapshot = activity.snapshot?.replace /&quot;/g, '"'
      activity


  constructor:(options={})->

    options.view    = new ActivityAppView
    options.appInfo =
      name          : 'Activity'

    super options

    @currentFilter     = activityTypes
    @appStorage        = new AppStorage 'Activity', '1.0'

    @mainController = @getSingleton 'mainController'

    if @mainController.appIsReady then @putListeners()
    else @mainController.on 'FrameworkIsReady', => @putListeners()

  putListeners:->
    activityController = @getSingleton('activityController')
    activityController.on   "ActivityListControllerReady", @attachEvents.bind @

    # Do we really need this? ~ GG
    # activityController.once "ActivityListControllerReady", @bound "populateActivity"

  loadView:->
    @populateActivity() if @listController

  resetList:->

    lastFrom = null
    lastTo   = null
    @listController.removeAllItems()

  setFilter:(type) -> @currentFilter = if type? then [type] else activityTypes

  getFilter: -> @currentFilter

  ownActivityArrived:(activity)-> @listController.ownActivityArrived activity

  fetchCurrentGroup:(callback)-> callback @currentGroupSlug

  attachEvents:(controller)->

    @listController    = controller
    activityController = @getSingleton('activityController')

    controller.on 'LazyLoadThresholdReached', @continueLoadingTeasers.bind @
    controller.on 'teasersLoaded', @teasersLoaded.bind @

    @getView().widgetController.on "FakeActivityHasArrived", (activity)->
      controller.fakeActivityArrived activity

    @getView().widgetController.on "OwnActivityHasArrived", @ownActivityArrived.bind @

    activityController.on 'ActivitiesArrived', @bound "activitiesArrived"

    KD.whoami().on "FollowedActivityArrived", (activityId) =>
      KD.remote.api.CActivity.one {_id: activityId}, (err, activity) =>
        if activity.constructor.name in @getFilter()
          activities = clearQuotes [activity]
          controller.followedActivityArrived activities.first

    @getView().innerNav.on "NavItemReceivedClick", (data)=>
      @resetList()
      @setFilter data.type
      @populateActivity()

  isExempt:(callback)->

    @appStorage.fetchStorage (storage) =>
      flags  = KD.whoami().globalFlags
      exempt = flags?.indexOf 'exempt'
      exempt = (exempt? and exempt > -1) or storage.getAt 'bucket.showLowQualityContent'
      callback exempt

  fetchActivitiesDirectly:(options = {})->

    KD.time "Activity fetch took"
    options = to : options.to or Date.now()

    @fetchActivity options, (err, teasers)=>
      isLoading = no
      @listController.hideLazyLoader()
      KD.timeEnd "Activity fetch took"
      @mainController.emit "AppIsReady"

      if err or teasers.length is 0
        warn "An error occured:", err  if err
        @listController.showNoItemWidget()
      else
        @listController.listActivities teasers

  fetchActivitiesFromCache:(options = {})->
    @fetchCachedActivity options, (err, cache)=>
      isLoading = no
      if err or cache.length is 0
        warn err  if err
        @listController.hideLazyLoader()
        @listController.showNoItemWidget()
      else
        @sanitizeCache cache, (err, cache)=>
          @listController.hideLazyLoader()
          @listController.listActivitiesFromCache cache

  populateActivity:(options = {})->

    return if isLoading
    isLoading = yes
    @listController.showLazyLoader()
    @listController.hideNoItemWidget()

    currentGroup = @getSingleton('groupsController').getCurrentGroupData()
    slug = currentGroup.getAt 'slug'

    unless slug is 'koding'
      # options.group = slug
      @fetchActivitiesDirectly options

    else
      @isExempt (exempt)=>
        if exempt or @getFilter() isnt activityTypes
          @fetchActivitiesDirectly options
        else
          @fetchActivitiesFromCache options

  sanitizeCache:(cache, callback)->

    activities = clearQuotes cache.activities

    KD.remote.reviveFromSnapshots activities, (err, instances)->

      for activity,i in activities
        cache.activities[activity._id] or= {}
        cache.activities[activity._id].teaser = instances[i]

      callback null, cache

  fetchActivity:(options = {}, callback)->

    options       =
      limit       : options.limit    or 20
      to          : options.to       or Date.now()
      facets      : options.facets   or @getFilter()
      lowQuality  : options.exempt   or no
      originId    : options.originId or null
      sort        :
        createdAt : -1

    KD.remote.api.CActivity.fetchFacets options, (err, activities)->
      if err then callback err
      else
        KD.remote.reviveFromSnapshots clearQuotes(activities), callback

  # Fetches activities that occur when user is disconnected.
  fetchSomeActivities:(options = {}) ->

    lastItemCreatedAt = @listController.getLastItemTimeStamp()

    selector       =
      createdAt    :
        $lte       : new Date
        $gt        : options.createdAt or lastItemCreatedAt
      type         : { $in : options.facets or @getFilter() }
      isLowQuality : { $ne : options.exempt or no }

    options       =
      limit       : 20
      sort        :
        createdAt : -1

    KD.remote.api.CActivity.some selector, options, (err, activities) =>
      if err then warn err
      else
        # FIXME: SY
        # if it is exact 20 there may be other items
        # put a separator and check for new items in between
        if activities.length is 20
          warn "put a separator in between new and old activities"

        @activitiesArrived activities.reverse()

  fetchCachedActivity:(options = {}, callback)->

    $.ajax
      url     : "/-/cache/#{options.slug or 'latest'}"
      cache   : no
      error   : (err)->   callback? err
      success : (cache)->
        cache.overview.reverse()  if cache?.overview
        callback null, cache

  continueLoadingTeasers:->

    unless isLoading
      if @listController.itemsOrdered.last
        lastItemData = @listController.itemsOrdered.last.getData()
        # memberbucket data has no serverside model it comes from cache
        # so it has no meta, that's why we check its date by its overview
        lastDate = if lastItemData.createdAtTimestamps
          new Date lastItemData.createdAtTimestamps[0]
        else
          new Date lastItemData.meta.createdAt
      else
        lastDate = new Date

      lastTimeStamp = lastDate.getTime()
      @populateActivity {slug : "before/#{lastTimeStamp}", to: lastTimeStamp}

  teasersLoaded:->

    unless @listController.scrollView.hasScrollBars()
      @continueLoadingTeasers()

  createContentDisplay:(activity, callback=->)->
    controller = switch activity.bongo_.constructorName
      when "JStatusUpdate" then @createStatusUpdateContentDisplay activity
      when "JCodeSnip"     then @createCodeSnippetContentDisplay activity
      when "JDiscussion"   then @createDiscussionContentDisplay activity
      when "JBlogPost"     then @createBlogPostContentDisplay activity
      when "JTutorial"     then @createTutorialContentDisplay activity
    @utils.defer -> callback contentDisplayController

  showContentDisplay:(contentDisplay)->
    contentDisplayController = @getSingleton "contentDisplayController"
    contentDisplayController.emit "ContentDisplayWantsToBeShown", contentDisplay
    return contentDisplayController

  createStatusUpdateContentDisplay:(activity)->
    @showContentDisplay new ContentDisplayStatusUpdate
      title : "Status Update"
      type  : "status"
    ,activity

  createBlogPostContentDisplay:(activity)->
    @showContentDisplay new ContentDisplayBlogPost
      title : "Blog Post"
      type  : "blogpost"
    ,activity

  createCodeSnippetContentDisplay:(activity)->
    @showContentDisplay new ContentDisplayCodeSnippet
      title : "Code Snippet"
      type  : "codesnip"
    ,activity

  createDiscussionContentDisplay:(activity)->
    @showContentDisplay new ContentDisplayDiscussion
      title : "Discussion"
      type  : "discussion"
    ,activity

  createTutorialContentDisplay:(activity)->
    @showContentDisplay new ContentDisplayTutorial
      title : "Tutorial"
      type  : "tutorial"
    ,activity

  streamByIds:(ids, callback)->

    selector = _id : $in : ids
    KD.remote.api.CActivity.streamModels selector, {}, (err, model) =>
      if err then callback err
      else
        unless model is null
          callback null, model[0]
        else
          callback null, null

  fetchTeasers:(selector,options,callback)->

    KD.remote.api.CActivity.some selector, options, (err, data) =>
      if err then callback err
      else
        data = clearQuotes data
        KD.remote.reviveFromSnapshots data, (err, instances)->
          if err then callback err
          else
            callback instances

  unhideNewItems: ->
    @listController?.activityHeader.updateShowNewItemsLink yes

  getNewItemsCount: (callback) ->
    callback? @listController?.activityHeader?.getNewItemsCount() or 0
