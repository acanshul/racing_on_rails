module TeamsHelper
  # Show team contact with email, if we have one
  def link_to_contact(team)
    if team.contact_email.present?
      mail_to team.contact_email, team.contact_name
    else
      team.contact_name
    end
  end
end
