module Card
	class Pointer < Base

	  def cacheable?
      false
    end
	  
	  def pointees
	    links = content.split(/\n+/).map{ |x| x.gsub(/\[\[|\]\]/,'')}
	    links.empty? ? [''] : links
	  end
	  
	end
end