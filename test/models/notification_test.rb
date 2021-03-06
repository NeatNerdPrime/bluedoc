# frozen_string_literal: true

require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @actor = create(:user)
    mock_current(user: @actor)

    @user = create(:user)
  end

  test "allow_type?" do
    assert_equal false, Notification.allow_type?("foo")

    %w[add_member].each do |notify_type|
      assert_equal true, Notification.allow_type?(notify_type)
    end
  end

  test "email" do
    user = create(:user)
    note = create(:notification, user: user)
    assert_equal user.email, note.email
  end

  test "actor_name" do
    actor = create(:user)
    note = Notification.new(actor: actor)
    assert_equal actor.name, note.actor_name

    assert_nil Notification.new(actor: nil).actor_name
  end

  test "track_notification" do
    group = create(:group)
    repo = create(:repository, user: group)
    member = create(:member, subject: repo, user: @user)

    mock_current user: @actor

    assert_enqueued_emails 1 do
      Notification.track_notification(:add_member, member, user_id: @user.id, meta: { foo: "bar" })
    end

    assert_tracked_notifications :add_member, target: member, user_id: @user.id, actor_id: @actor.id, meta: { foo: "bar" }
  end

  test "read_targets" do
    user = create(:user)
    note0 = create(:notification, target_type: "Doc", target_id: 1, user: user)
    note1 = create(:notification, target_type: "Doc", target_id: 2, user: user)
    note2 = create(:notification, target_type: "Doc", target_id: 3)
    note3 = create(:notification, target_type: "Comment", target_id: 2)

    Notification.read_targets(nil, target_type: "Doc", target_id: [1, 2, 3])
    Notification.read_targets(user, target_type: "Doc", target_id: [1, 2, 3])
    note0.reload
    assert_not_nil note0.read_at
    note1.reload
    assert_not_nil note1.read_at
    note2.reload
    assert_nil note2.read_at
    note3.reload
    assert_nil note3.read_at
  end

  test "cannot track with user not ability to read target" do
    # private repo
    group = create(:group)
    repo = create(:repository, user: group, privacy: :private)
    user = create(:user)

    # not member, not receive notifications for private repo
    assert_no_changes -> { Notification.where(notify_type: :repo_import).count } do
      Notification.track_notification(:repo_import, repo, user: user, actor_id: @actor.id)
    end

    # add user as group reader, to have ability to read repo
    group.add_member(user, :reader)
    assert_changes -> { Notification.where(notify_type: :repo_import).count } do
      Notification.track_notification(:repo_import, repo, user_id: user.id, actor_id: @actor.id)
    end
    assert_tracked_notifications :repo_import, target: repo, user_id: user.id, actor_id: @actor.id
  end

  test "cannot track with user, actor in same" do
    user = create(:user)
    member = create(:member)

    Notification.track_notification(:add_member, member, user_id: user.id, actor_id: user.id)
    assert_equal 0, Notification.where(user_id: user.id).count

    mock_current user: user
    Notification.track_notification(:add_member, member, user_id: user.id)
    assert_equal 0, Notification.where(user_id: user.id).count
  end

  test "type : add_member of Group" do
    group = create(:group)
    member = create(:member, subject: group)
    note = create(:notification, notify_type: :add_member, target: member)
    assert_equal group.to_url, note.target_url

    assert_equal "#{note.actor.name} has added you as a member of [#{group.name}]", note.mail_body
    assert_equal "#{note.actor.name} has added you as a member of [#{group.name}]", note.mail_title
    assert_equal "add_member-User-#{group.id}", note.mail_message_id
  end

  test "type : add_member of Repository" do
    repo = create(:repository)
    member = create(:member, subject: repo)
    note = create(:notification, notify_type: :add_member, target: member)
    assert_equal repo.to_url, note.target_url

    assert_equal "#{note.actor.name} has added you as a member of [#{repo.user.name} / #{repo.name}]", note.mail_body
    assert_equal "#{note.actor.name} has added you as a member of [#{repo.user.name} / #{repo.name}]", note.mail_title
    assert_equal "add_member-Repository-#{repo.id}", note.mail_message_id
  end

  test "repo_import" do
    repo = create(:repository)
    note = create(:notification, notify_type: :repo_import, target: repo, meta: { status: :success })

    assert_equal repo.to_url, note.target_url
    assert_equal "Repository [#{repo.user.name} / #{repo.name}] has been imported success.", note.mail_body.strip
    assert_equal "Repository [#{repo.user.name} / #{repo.name}] has been imported success.", note.mail_title.strip
    assert_equal "repo_import-Repository-#{repo.id}", note.mail_message_id
    assert_equal "", note.target_mention_fragment
  end

  test "comment Doc" do
    doc = create(:doc)
    actor = create(:user)
    comment = create(:comment, commentable: doc)
    note = create(:notification, notify_type: :comment, target: comment, actor: actor)

    assert_equal comment.to_url, note.target_url
    assert_html_equal "<p><a style=\"font-weight:bold; color: #333\" href=\"#{comment.to_url}\">#{comment.commentable_title}</a></p><p><strong>#{note.actor_name}</strong> said:</p> #{comment.body_html}", note.mail_body
    assert_equal "#{comment.commentable_title} got a comment.", note.mail_title
    assert_equal "comment-#{comment.commentable_type}-#{comment.commentable_id}", note.mail_message_id
    assert_equal comment.body_html, note.target_mention_fragment
  end

  test "mention Comment" do
    doc = create(:doc)
    user = create(:user)
    actor = create(:user)
    comment = create(:comment, commentable: doc, body: "Hello @#{user.slug}")
    note = create(:notification, notify_type: :mention, target: comment, actor: actor)

    assert_equal comment.to_url, note.target_url
    assert_html_equal "<p><strong>#{note.actor_name}</strong> mentioned you:</p><div>#{note.target_mention_fragment}</div>", note.mail_body
    assert_equal "#{comment.commentable_title} got a comment.", note.mail_title
    assert_equal "comment-#{comment.commentable_type}-#{comment.commentable_id}", note.mail_message_id
    assert_equal comment.body_html, note.target_mention_fragment
  end

  test "mention Doc" do
    user = create(:user)
    doc = create(:doc, body: "Hello @#{user.slug}\n\n@#{user.slug} hello")
    actor = create(:user)
    note = create(:notification, notify_type: :mention, target: doc, user: user, actor: actor)

    assert_equal doc.to_url, note.target_url
    assert_equal "Hello @#{user.slug}<br /><br />@#{user.slug} hello", note.target_mention_fragment
    assert_html_equal "<p><strong>#{note.actor_name}</strong> has mentioned you in [#{doc.title}].</p><div>#{note.target_mention_fragment}</div>", note.mail_body
    assert_equal "#{doc.title} content has mentioned you.", note.mail_title
    assert_equal "comment-Doc-#{doc.id}", note.mail_message_id
  end

  test "issue_assign" do
    issue = create(:issue)
    actor = create(:user)
    note = create(:notification, notify_type: :issue_assign, target: issue, actor: actor)

    assert_equal issue.to_url, note.target_url
    assert_equal "issue_assign-Issue-#{issue.id}", note.mail_message_id
    assert_equal issue.body_html, note.target_mention_fragment
    assert_html_equal "<p><strong>#{note.actor_name}</strong> has assigned issue to you:</p><a href=\"#{Setting.host}/notifications/#{note.id}\">#{issue.issue_title}</a>", note.mail_body
    assert_equal "#{issue.issue_title} has assigned to you.", note.mail_title
  end

  test "new_issue" do
    issue = create(:issue)
    actor = create(:user)
    note = create(:notification, notify_type: :new_issue, target: issue, actor: actor)

    assert_equal issue.to_url, note.target_url
    assert_equal "new_issue-Issue-#{issue.id}", note.mail_message_id
    assert_equal issue.body_html, note.target_mention_fragment
    assert_html_equal "<p><strong>#{note.actor_name}</strong> has opened new issue:</p><a href=\"#{Setting.host}/notifications/#{note.id}\">#{issue.issue_title}</a>", note.mail_body
    assert_equal "#{issue.issue_title} has opened new issue.", note.mail_title
  end

  test "close_issue" do
    issue = create(:issue)
    actor = create(:user)
    note = create(:notification, notify_type: :close_issue, target: issue, actor: actor)

    assert_equal issue.to_url, note.target_url
    assert_equal "close_issue-Issue-#{issue.id}", note.mail_message_id
    assert_equal issue.body_html, note.target_mention_fragment
    assert_html_equal "<p><strong>#{note.actor_name}</strong> has closed issue:</p><a href=\"#{Setting.host}/notifications/#{note.id}\">#{issue.issue_title}</a>", note.mail_body
    assert_equal "#{issue.issue_title} has closed issue.", note.mail_title
  end

  test "reopen_issue" do
    issue = create(:issue)
    actor = create(:user)
    note = create(:notification, notify_type: :reopen_issue, target: issue, actor: actor)

    assert_equal issue.to_url, note.target_url
    assert_equal "reopen_issue-Issue-#{issue.id}", note.mail_message_id
    assert_equal issue.body_html, note.target_mention_fragment
    assert_html_equal "<p><strong>#{note.actor_name}</strong> has reopened issue:</p><a href=\"#{Setting.host}/notifications/#{note.id}\">#{issue.issue_title}</a>", note.mail_body
    assert_equal "#{issue.issue_title} has reopened issue.", note.mail_title
  end
end
