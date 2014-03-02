class StackView extends KDView

  constructor:(options={}, data)->
    options.cssClass = KD.utils.curry 'environment-stack', options.cssClass
    super options, data

  viewAppended:->

    {stack} = @getOptions()
    title   = stack.meta?.title
    number  = if stack.sid > 0 then "#{stack.sid}." else "default"
    group   = KD.getGroup().title
    title or= "Your #{number} stack on #{group}"

    @addSubView title = new KDView
      cssClass : 'stack-title'
      partial  : title

    @addSubView toggle = new KDButtonView
      title    : 'Hide details'
      cssClass : 'stack-toggle solid on clear'
      iconOnly : yes
      iconClass: 'toggle'
      callback : =>
        if @getHeight() <= 50
          @setHeight @getProperHeight()
          toggle.setClass 'on'
        else
          toggle.unsetClass 'on'
          @setHeight 48
        KD.utils.wait 300, @bound 'updateView'

    @addSubView context = new KDButtonView
      cssClass  : 'stack-context solid clear'
      style     : 'comment-menu'
      title     : ''
      iconOnly  : yes
      delegate  : this
      iconClass : "cog"
      callback  : (event)=>
        new JContextMenu
          cssClass    : 'environments'
          event       : event
          delegate    : this
          x           : context.getX() - 138
          y           : context.getY() + 40
          arrow       :
            placement : 'top'
            margin    : 150
        ,
          'Show stack recipe'  :
            callback           : @bound 'dumpStack'
          'Clone this stack'   :
            callback           : -> log 'clone'
          'Create a new stack' :
            callback           : -> log 'lomolo'

    # Main scene for DIA
    @addSubView @scene = new EnvironmentScene @getData().stack

    # Rules Container
    @rules = new EnvironmentRuleContainer
    @scene.addContainer @rules

    # Domains Container
    @domains = new EnvironmentDomainContainer
    @scene.addContainer @domains
    @domains.on 'itemAdded', @lazyBound 'updateView', yes

    # VMs / Machines Container
    @vms = new EnvironmentMachineContainer
    @scene.addContainer @vms

    KD.getSingleton("vmController").on 'VMListChanged', =>
      EnvironmentDataProvider.get (data) => @loadContainers data

    # Rules Container
    @extras = new EnvironmentExtraContainer
    @scene.addContainer @extras

    @loadContainers()

  loadContainers: (data)->

    env     = data or @getData()
    orphans = domains: [], vms: []
    {stack, isDefault} = @getOptions()

    # Add rules
    @rules.removeAllItems()
    @rules.addItem rule  for rule in env.rules

    # Add domains
    @domains.removeAllItems()
    for domain in env.domains
      if domain.stack is stack._id or isDefault
      then @domains.addDomain domain
      else orphans.domains.push domain

    # Add vms
    @vms.removeAllItems()
    for vm in env.vms
      if vm.stack is stack._id or isDefault
      then @vms.addItem title:vm.alias
      else orphans.vms.push vm

    # Add extras
    @extras.removeAllItems()
    @extras.addItem extra  for extra in env.extras

    # log "ORPHANS", orphans

    @setHeight @getProperHeight()
    KD.utils.wait 300, =>
      @_inProgress = no
      @updateView yes

  dumpStack:->

    {containers, connections} = @scene

    dump = {}

    for i, container of containers
      name = EnvironmentScene.containerMap[container.constructor.name]
      dump[name] = []
      for j, dia of container.dias
        dump[name].push \
          if name is 'domains'
            title   : dia.data.title
            aliases : dia.data.aliases
          else dia.data

    new KDModalView
      cssClass : 'recipe'
      title    : 'Stack recipe'
      width    : 600
      content  : """
        <pre>
        #{hljs.highlight('yaml',jsyaml.dump(dump)).value}
        </pre>
        """


  updateView:(dataUpdated = no)->

    @scene.updateConnections()  if dataUpdated

    if @getHeight() > 50
      @setHeight @getProperHeight()

    @scene.highlightLines()
    @scene.updateScene()

  getProperHeight:->
    (Math.max.apply null, \
      (box.diaCount() for box in @scene.containers)) * 45 + 170
