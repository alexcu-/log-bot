Users           = require './users'
Roles           = require './roles'
{EventEmitter}  = require 'events'
###
This class is responsible for handling bot admin commands
###
module.exports = class CommandProcessor extends EventEmitter
  ###
  RegExp's for the kinds of parameters accepted in the processor
  ###
  PARAMS =
    USER: /<@([A-Z0-9]+)>/g                           # A slack user
    ROLE: /(?:(?:["“'‘])([A-Z\_\s]+)(?:["”'’]))/g     # A role (wrapped in quotes)
    TRIGGER: /(?:(?:["“'‘])([A-Z\_\s]+)(?:["”'’]))/g  # A trigger (wrapped in quotes)

  ###
  Command replacement matches. Plurals must come first such that
  they will reduce down to their singular equivalents.
  ###
  MATCH_REPLACEMENTS =
    '[USERS]': /([USER],?\s?)+/
    '[USER]' : PARAMS.USER
    '[ROLES]': /([ROLE],?\s?)+/
    '[ROLE]' : PARAMS.ROLE
    '[TRIGGER]': PARAMS.TRIGGER

  ###
  Commands mapped to their functions
  Where [USER] is present, a slack user will be matched
  Where [ROLE] is present, a user role will be matched
  Where [ROLE] is present, a trigger will be matched
  ###
  COMMANDS =
    # Role-based commands
    'ASSIGN [USER] ROLE [ROLE]':
      description:  'Assigns the provided user the given role'
      func:         'assignUserRole'
    'ADD ROLE [ROLES]':
      description:  'Makes me aware of a new role'
      func:         'addRole'
    'DROP ROLE [ROLES]':
      description:  'Drops a role(s) that I currently know of. \
                     Warning: any user that has this role will be stripped of that role.'
      func:         'dropRole'
    'GET ROLE FOR [USERS]':
      description:  'Gets the role for the given user'
      func:         'getRolesForUsers'
    'GET ALL ROLES':
      description:  'Gets every role that I know about'
      func:         'getAllRoles'
    # Log-based commands
    'GET LOGS FOR [USERS]':
      description:  'Gets each log for each user provided'
      func:         'getLogsForUsers'
    'GET LOGS':
      description:  'Gets every log that I know about'
      func:         'getAllLogs'
    # Triggers
    'ASSIGN [ROLE] TRIGGER [TRIGGER]':
      description:  'Assigns the role provided a new trigger'
      func:         'assignRoleTrigger'
    # Help
    'HELP':
      description:  'Shows this help menu'
      func:         'getHelp'
  ###
  Assigns the user provided a role
  @param  [object]  args  The command args
  ###
  __assignUserRole: (args) =>
    userId  = args.users[0]
    role    = args.roles[0]
    Users.assignRole(userId, role)
      .then (success) =>
        @_success success
      .fail (err) =>
        @_fail err
  ###
  Adds a new role
  @param  [object]  args  The command args
  ###
  __addRole: (args) ->
    roles = args.roles
    while roles.length > 0
      role = roles.shift()
      Roles.add(role)
        .then (success) =>
          @_success success
        .fail (err) =>
          @_fail err
  ###
  Drops an existing role
  @param  [object]  args  The command args
  ###
  __dropRole: (args) ->
    roles = args.roles
    while roles.length > 0
      role = roles.shift()
      Roles.drop(role)
        .then (success) =>
          @_success success
        .fail (err) =>
          @_fail err
  ###
  Gets all roles
  ###
  __getAllRoles: ->
    Roles.all().then (roles) =>
      if roles.length is 0
        return @_success "There are no roles I know of"
      @_success "Here are all the roles: \"#{roles.join('\", \"')}\""
  ###
  Gets the roles for the given users
  @param  [object]  args  The command args
  ###
  __getRolesForUsers: (args) ->
    users = args.users
    while users.length > 0
      userId = users.shift()
      Users.find(userId)
        .then (user) =>
          hasRole = user.role?
          if hasRole
            @_success "Role for #{user.profile.real_name} is \"#{user.role}\""
          else
            @_success "#{user.profile.real_name} is not yet assigned a role"
        .fail (err) =>
          @_fail err
  ###
  Gets the logs for the given users
  @param  [object]  args  The command args
  ###
  __getLogsForUsers: (args) ->
    "TODO: Implement __getLogsForUsers\t args = (#{JSON.stringify args})"
  ###
  Gets all logs available
  @param  [object]  args  The command args
  ###
  __getAllLogs: (args) ->
    "TODO: Implement __getAllLogs\t args = (#{JSON.stringify args})"
  ###
  Assigns the role the provided trigger
  @param  [object]  args  The command args
  ###
  __assignRoleTrigger: (args) ->
    triggerKey  = args.trigger[0]
    role        = args.roles[0]
    Roles.associateTrigger(role, triggerKey, @_logBot.triggerManager)
      .then (success) =>
        @_success success
      .fail (err) =>
        @_fail err
  ###
  Gets descriptions for every command
  ###
  __getHelp: (args) ->
    string = "I understand all of these commands...\n"
    for command, commandData of COMMANDS
      string += "`#{command}`\n_#{commandData.description}_\n\n"
    @_success string

  ###
  Generates a Regular Expression for the given command by converting its
  matched replacements with the replacements to match
  @param  [string]  command The input command
  @returns  [RegExp]  A regular expression representing the command
  ###
  _regExpForCommand: (command) ->
    # Replace param match replacements with actual RegEx
    for match, regExp of MATCH_REPLACEMENTS
      # Replace each match with it's matched RegExp
      command = command.replace match, regExp.source
    # Return the command as a RegExp
    RegExp(command)

  ###
  Emits a command fail message
  @param  [string]  message Fail message
  ###
  _fail: (message) =>
    @emit 'commandParsed', { message: message, success: false }

  ###
  Emits a command success message
  @param  [string]  message Success message
  ###
  _success: (message) =>
    @emit 'commandParsed', { message: message, success: true }

  ###
  Checks for a match between the input and the command provided
  @param  [string]  input Input string
  @param  [string]  command Regular Expression command
  @returns  [boolean] True on match, false otherwise
  ###
  _match: (input, command) =>
    matches = input.match(@_regExpForCommand command)
    matches?.length > 0

  ###
  Strips a parameter list out of the command from all possible parameters
  @param  [string]  input Input string to parse
  @returns  [array] An array of user ids stripped
  ###
  _stripParams: (input) ->
    stripped = {}
    for paramType, regExp of PARAMS
      paramType = paramType.toLowerCase() + 's'
      while (match = regExp.exec(input))
        value = match[1]
        continue unless value?
        stripped[paramType] = [] unless stripped[paramType]?
        stripped[paramType].push value
    stripped

  ###
  Parses the input string for a command
  @param  [string]  input Input string
  ###
  parse: (input) =>
    if input?
      input = input.toUpperCase()
      for command, commandData of COMMANDS
        if @_match input, command
          params = @_stripParams input
          try
            # Execute the command
            return @['__' + commandData.func](params)
          catch e
            return @_fail e.message
      @_fail "Invalid admin command!"

  ###
  @param  [LogBot]  logBot  The log bot connected to this command processor
  ###
  constructor: (@_logBot) ->
    return