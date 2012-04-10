require 'estraierpure'

module EstraierPure
  class NodeResult
    include Enumerable

    def each
      for i in 0...self.doc_num
        yield self.get_doc(i)
      end
    end
  end
end
