module ApplicationHelper
  def link_to_wiki(content)
    link_to content, "https://github.com/dingbat/nsrails/wiki"
  end

  def link_to_source(content)
    link_to content, "https://github.com/dingbat/nsrails"
  end

  def link_to_screencast(content)
    link_to content, "http://vimeo.com/dq/nsrails"
  end
  
  def fork_me_ribbon
    image_tag "forkme.png", :id=>"ribbon", :alt=>"Fork me on GitHub"
  end
end
