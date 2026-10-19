USE Datosofis
GO

if exists (select * from mytitles
                 where price > $50.00)
     update mytitles set price = price * $0.90
Else
      print ‘Todos los títulos son menor a $50.00’
 GO

 --hola