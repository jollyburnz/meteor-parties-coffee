# All Tomorrow's Parties -- server
Meteor.publish "directory", ->
  Meteor.users.find {},
    fields:
      emails: 1
      profile: 1


Meteor.publish "parties", ->
  Parties.find $or: [
    public: true
  ,
    invited: @userId
  ,
    owner: @userId
  ]

