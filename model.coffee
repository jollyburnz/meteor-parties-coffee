# All Tomorrow's Parties -- data model
# Loaded on both the client and the server

#/////////////////////////////////////////////////////////////////////////////
# Parties

#
#  Each party is represented by a document in the Parties collection:
#    owner: user id
#    x, y: Number (screen coordinates in the interval [0, 1])
#    title, description: String
#    public: Boolean
#    invited: Array of user id's that are invited (only if !public)
#    rsvps: Array of objects like {user: userId, rsvp: "yes"} (or "no"/"maybe")
#
Parties = new Meteor.Collection("parties")
Parties.allow
  insert: (userId, party) ->
    false # no cowboy inserts -- use createParty method

  update: (userId, parties, fields, modifier) ->
    _.all parties, (party) ->
      return false  if userId isnt party.owner # not the owner
      allowed = ["title", "description", "x", "y"]
      return false  if _.difference(fields, allowed).length # tried to write to forbidden field

      # A good improvement would be to validate the type of the new
      # value of the field (and if a string, the length.) In the
      # future Meteor will have a schema system to makes that easier.
      true


  remove: (userId, parties) ->
    not _.any(parties, (party) ->

      # deny if not the owner, or if other people are going
      party.owner isnt userId or attending(party) > 0
    )

attending = (party) ->
  (_.groupBy(party.rsvps, "rsvp").yes or []).length

Meteor.methods

  # options should include: title, description, x, y, public
  createParty: (options) ->
    options = options or {}
    throw new Meteor.Error(400, "Required parameter missing")  unless typeof options.title is "string" and options.title.length and typeof options.description is "string" and options.description.length and typeof options.x is "number" and options.x >= 0 and options.x <= 1 and typeof options.y is "number" and options.y >= 0 and options.y <= 1
    throw new Meteor.Error(413, "Title too long")  if options.title.length > 100
    throw new Meteor.Error(413, "Description too long")  if options.description.length > 1000
    throw new Meteor.Error(403, "You must be logged in")  unless @userId
    Parties.insert
      owner: @userId
      x: options.x
      y: options.y
      title: options.title
      description: options.description
      public: !!options.public
      invited: []
      rsvps: []


  invite: (partyId, userId) ->
    party = Parties.findOne(partyId)
    throw new Meteor.Error(404, "No such party")  if not party or party.owner isnt @userId
    throw new Meteor.Error(400, "That party is public. No need to invite people.")  if party.public
    if userId isnt party.owner and not _.contains(party.invited, userId)
      Parties.update partyId,
        $addToSet:
          invited: userId

      from = contactEmail(Meteor.users.findOne(@userId))
      to = contactEmail(Meteor.users.findOne(userId))
      if Meteor.isServer and to

        # This code only runs on the server. If you didn't want clients
        # to be able to see it, you could move it to a separate file.
        Email.send
          from: "noreply@example.com"
          to: to
          replyTo: from or `undefined`
          subject: "PARTY: " + party.title
          text: "Hey, I just invited you to '" + party.title + "' on All Tomorrow's Parties." + "\n\nCome check it out: " + Meteor.absoluteUrl() + "\n"


  rsvp: (partyId, rsvp) ->
    throw new Meteor.Error(403, "You must be logged in to RSVP")  unless @userId
    throw new Meteor.Error(400, "Invalid RSVP")  unless _.contains(["yes", "no", "maybe"], rsvp)
    party = Parties.findOne(partyId)
    throw new Meteor.Error(404, "No such party")  unless party

    # private, but let's not tell this to the user
    throw new Meteor.Error(403, "No such party")  if not party.public and party.owner isnt @userId and not _.contains(party.invited, @userId)
    rsvpIndex = _.indexOf(_.pluck(party.rsvps, "user"), @userId)
    if rsvpIndex isnt -1

      # update existing rsvp entry
      if Meteor.isServer

        # update the appropriate rsvp entry with $
        Parties.update
          _id: partyId
          "rsvps.user": @userId
        ,
          $set:
            "rsvps.$.rsvp": rsvp

      else

        # minimongo doesn't yet support $ in modifier. as a temporary
        # workaround, make a modifier that uses an index. this is
        # safe on the client since there's only one thread.
        modifier = $set: {}
        modifier.$set["rsvps." + rsvpIndex + ".rsvp"] = rsvp
        Parties.update partyId, modifier

    # Possible improvement: send email to the other people that are
    # coming to the party.
    else

      # add new rsvp entry
      Parties.update partyId,
        $push:
          rsvps:
            user: @userId
            rsvp: rsvp



#/////////////////////////////////////////////////////////////////////////////
# Users
displayName = (user) ->
  return user.profile.name  if user.profile and user.profile.name
  user.emails[0].address

contactEmail = (user) ->
  return user.emails[0].address  if user.emails and user.emails.length
  return user.services.facebook.email  if user.services and user.services.facebook and user.services.facebook.email
  null
