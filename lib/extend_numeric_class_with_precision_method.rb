class Numeric
  def precision( dp )
    return self.round if ( dp == 0 )
    mul = 10.0 ** dp
    ( self * mul ).round / mul
  end
end
