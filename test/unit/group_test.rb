require_relative 'test_helper'

class GroupTest < ActiveSupport::TestCase
  fixtures :groups, :users, :profiles, :memberships, :sites, :keys

  def teardown
    Group.clear_key_cache # required! see CastleGates README
  end

  def test_memberships
    g = Group.create :name => 'fruits'
    u = users(:blue)
    assert_equal 0, g.users.size, 'there should be no users'
    assert_raises(Exception, '<< should raise exception not allowed') do
      g.users << u
    end
    g.add_user! u
    g.add_user! users(:red)

    assert u.member_of?(g), 'user should be member of group'

    g.memberships.each do |m|
      m.destroy
    end
    g.reload
    assert_equal 0, g.users.size, 'there should be no users'
  end

  def test_missing_name
    g = Group.create
    assert !g.valid?, 'group with no name should not be valid'
  end

  def test_duplicate_name
    g1 = Group.create :name => 'fruits'
    assert g1.valid?, 'group should be valid'

    g2 = Group.create :name => 'fruits'
    assert g2.valid? == false, 'group should not be valid'
  end

  def test_try_to_create_group_with_same_name_as_user
    u = User.find(1)
    assert u.login, 'user should be valid'

    g = Group.create :name => u.login
    assert g.valid? == false, 'group should not be valid'
    assert g.save == false, 'group should fail to save'
  end

  def test_cant_pester_private_group
    g = Group.create :name => 'riseup'
    g.revoke_access! :public => :view
    u = User.create :login => 'user'

    assert u.may?(:pester, g) == false, 'should not be able to pester private group'
  end

  def test_can_pester_public_group
    g = Group.create :name => 'riseup'
    g.grant_access! :public => [:view, :pester]
    g.reload
    u = User.create :login => 'user'

    assert u.may?(:pester, g) == true, 'should be able to pester private group'
  end

  def test_site_disabling_public_profiles_doesnt_affect_groups
    with_site(:local, :profiles => ["private"]) do
      u = users(:red)
      g = groups(:animals)

      g.grant_access! :public => :request_membership
      g.reload

      assert g.profiles.visible_by(u).public?
      assert g.has_access? :request_membership, u
    end
  end

  # disabled mocha test
  #def test_association_callbacks
  #  g = Group.create :name => 'callbacks'
  #  g.expects(:check_duplicate_memberships)
  #  u = users(:blue)
  #  g.add_user!(u)
  #end

  def test_committee_access
    g = groups(:public_group)
    assert_equal [groups(:public_committee)],
                 g.committees_for(users(:red)).sort_by{|c| c.id},
                 "should find 1 public committee"
    assert_equal [groups(:public_committee), groups(:private_committee)].sort_by{|c| c.id},
                 g.committees_for(users(:blue)).sort_by{|c| c.id},
                 "should find 2 committee with private access"
  end

  def test_councils
    group = groups(:rainbow)
    committee = groups(:cold)
    blue = users(:blue)
    red  = users(:red)

    assert_equal committee.parent, group
    assert blue.direct_member_of?(committee)
    assert !red.direct_member_of?(committee)

    assert red.may?(:admin, group)
    assert blue.may?(:admin, group)
    assert !group.has_a_council?

    assert_nothing_raised do
      group.add_council!(committee)
    end
    red.clear_cache
    blue.clear_cache
    assert !red.may?(:admin, group)
    assert blue.may?(:admin, group)
    assert group.has_a_council?
  end

  def test_name_change
    group = groups(:true_levellers)
    user = users(:gerrard)

    version = user.version

    group.name = 'diggers'
    group.save!

    # note: if the group has a committee, and the user is a member of that
    # committee, then the user's version will increment by more than one,
    # since the committees also experience a name change.
    assert_equal version+1, user.reload.version, 'user version should increment on group name change'
  end

  def test_associations
    User.current = users(:blue)
    assert check_associations(Group)
    User.current = nil
  end

  def test_alphabetized
    assert_equal Group.all.size, Group.alphabetized('').size

    # find numeric group names
    assert_equal 0, Group.alphabetized('#').size
    Group.create :name => '1more'
    assert_equal 1, Group.alphabetized('#').size

    # case insensitive
    assert_equal Group.alphabetized('r').size, Group.alphabetized('R').size

    # nothing matches
    assert Group.alphabetized('z').empty?
  end

  def test_destroy
    g = Group.create :name => 'fruits'
    g.add_user! users(:blue)
    g.add_user! users(:red)
    g.reload

    page = DiscussionPage.create! :title => 'hello', :user => users(:blue), :owner => g
    assert_equal page.owner, g

    assert_difference 'Membership.count', -2 do
      g.destroy_by(users(:blue))
    end

    assert_nil page.reload.owner_id

    red = users(:red)
    assert_nil GroupLostUserActivity.for_all(red).find(:first),
      "there should be no user left group message"

    destroyed_act = GroupDestroyedActivity.for_all(red).unique.find(:first)
    assert destroyed_act, "there should exist a group destroyed activity message"

    assert_equal g.name, destroyed_act.groupname, "the activity should have the correct group name"
  end

  def test_avatar
    # must have GM installed
    if !GraphicsMagickTransmogrifier.new.available?
      puts "GraphicsMagick converter is not available. Either GraphicsMagick is not installed or it can not be started. Skipping GroupTest#test_avatar."
      return
    end

    group = nil
    assert_difference 'Avatar.count' do
      group = Group.create(
        :name => 'groupwithavatar',
        :avatar => Avatar.new(:image_file => upload_avatar('image.png'))
      )
    end

    group.reload
    assert group.avatar.image_file_data.size > 0
    avatar_id = group.avatar.id

    group.avatar.image_file = upload_avatar('photo.jpg')
    group.avatar.save!
    group.save!
    group.reload
    assert group.avatar.image_file_data.size > 0
    assert_equal avatar_id, group.avatar.id

    group.avatar.image_file = upload_avatar('bee.jpg')
    group.avatar.save!
    group.reload
    assert_equal avatar_id, group.avatar.id
    assert group.avatar.image_file_data.size > 0

    assert_difference 'Avatar.count', -1 do
      group.destroy_by(users(:red))
    end

  end

  def test_migrate_public_view
    group = Group.new
    assert group.valid?
  end

end
