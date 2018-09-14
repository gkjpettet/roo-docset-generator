#tag Module
Protected Module Dash
	#tag Method, Flags = &h21
		Private Sub CreateDatabase()
		  ' Create the Dash docset SQLite database.
		  
		  ' Get a FolderItem reference to where the SQLite DB will be stored.
		  Try
		    dbFile = DocsetRoot.Child("Contents").Child("Resources").Child("docSet.dsidx")
		  Catch err
		    QuitWithMessage("Unable to create the SQLite database file.")
		  End Try
		  
		  ' Create the DB file on disk.
		  db = New SQLiteDatabase
		  db.DatabaseFile = dbFile
		  If Not db.CreateDatabaseFile Then QuitWithMessage("Unable to create SQLite database: " + db.ErrorMessage)
		  
		  ' Connect to the empty DB.
		  If Not db.Connect Then
		    QuitWithMessage("Unable to connect to the newly created SQLite database: " + db.ErrorMessage)
		  End If
		  
		  ' Create the required table.
		  db.SQLExecute("CREATE TABLE searchIndex(id INTEGER PRIMARY KEY, name TEXT, type TEXT, path TEXT);")
		  If db.Error then
		    QuitWithMessage("Database error: " + db.ErrorMessage)
		  Else
		    db.Commit
		  End If
		  
		  ' Prevent duplicate entries.
		  db.SQLExecute("CREATE UNIQUE INDEX anchor ON searchIndex (name, type, path);")
		  If db.Error then
		    QuitWithMessage("Database error: " + db.ErrorMessage)
		  Else
		    db.Commit
		  End If
		  
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h1
		Protected Function EntityNameFromHTMLFile(f As Xojo.IO.FolderItem) As String
		  ' Takes an HTML file and finds the name of the entity.
		  ' E.g: for DateTime.monday? the entity would be `monday?`
		  ' Should be in the format: <h1>Class.entity</h1>
		  
		  Dim re As New RegEx
		  ' re.SearchPattern = "\<h1\>(.+\..+)\<\/h1\>"
		  re.SearchPattern = "\<h1\>(.+)\<\/h1\>"
		  
		  Dim html As String
		  Try
		    Dim tin As Xojo.IO.TextInputStream = Xojo.IO.TextInputStream.Open(f, Xojo.Core.TextEncoding.UTF8)
		    html = tin.ReadAll
		    tin.Close
		  Catch err
		    QuitWithMessage("Error opening TextInputStream (" + f.Path + ").")
		  End Try
		  
		  Dim match As RegExMatch = re.Search(html)
		  
		  If match <> Nil Then
		    Return match.SubExpressionString(1)
		  Else
		    Return ""
		  End If
		End Function
	#tag EndMethod

	#tag Method, Flags = &h1
		Protected Sub Generate()
		  If SourceRoot = Nil Or SourceRoot.Exists = False Then MsgBox("Dash.SourceRoot is invalid.")
		  If DocsetParent = Nil Or DocsetParent.Exists = False Then MsgBox("Dash.DocsetParent is invalid.")
		  
		  DocsetRoot = DocsetParent.Child(kDocsetName + ".docset")
		  
		  ' Delete any existing docset.
		  If DocsetRoot <> Nil And DocsetRoot.Exists Then
		    If FileSystem.ReallyDelete(DocsetRoot) <> 0 Then
		      MsgBox("Unable to delete `" + DocsetRoot.NativePath + "`.")
		      Quit
		    End If
		  End If
		  
		  ' Create the required folder structure.
		  Dim s As New Shell
		  s.Mode = 0 ' Synchronous.
		  Dim command As String = "mkdir -p " + DocsetRoot.NativePath + "/Contents/Resources/Documents/"
		  s.Execute(command)
		  
		  ' Get a reference to the newly created docset's documents root.
		  Try
		    DocsetDocsRoot = DocsetRoot.Child("Contents").Child("Resources").Child("Documents")
		    If DocsetDocsRoot = Nil Or Not DocsetDocsRoot.Exists Then
		      MsgBox("The docset Documents folder is invalid.")
		      Quit
		    End If
		  Catch
		    MsgBox("The docset Documents folder is invalid.")
		    Quit
		  End Try
		  
		  ' Copy the HTML documentation from the source to the docset documents root.
		  Dim e As FileSystem.Error
		  e = FileSystem.CopyTo(SourceRoot, DocsetDocsRoot)
		  If e <> FileSystem.Error.None Then
		    MsgBox("An error occurred whilst copying the HTML to the docset Documents folder.")
		    ' Delete the incomplete docset.
		    Call FileSystem.ReallyDelete(DocsetRoot)
		    Quit
		  End If
		  
		  ' Copy the info.plist to DocsetRoot/Contents/
		  Dim info As FolderItem = SpecialFolder.GetResource("info.plist")
		  If Not info.Exists Then
		    MsgBox("Unable to load the info.plist file.")
		    Quit
		  End If
		  e = FileSystem.CopyTo(info, DocsetRoot.Child("Contents"))
		  If e <> FileSystem.Error.None Then
		    MsgBox("An error occurred whilst attempting to copy the info.plist file to the docset.")
		    ' Delete the incomplete docset.
		    Call FileSystem.ReallyDelete(DocsetRoot)
		    Quit
		  End If
		  
		  ' Create the new database.
		  CreateDatabase
		  
		  ' Populate the database.
		  PopulateDatabase
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub PopulateDatabase()
		  Dim f, folder As Xojo.IO.FolderItem
		  Dim className, moduleName, name, path, type As String
		  
		  Dim tmp As FolderItem = DocsetDocsRoot.Child("docs")
		  If tmp = Nil Or Not tmp.Exists Then
		    QuitWithMessage("Invalid Documents structure (Dash.PopulateDatabase).")
		  End If
		  
		  Dim root As New Xojo.IO.FolderItem(tmp.NativePath.ToText)
		  
		  ' Control flow.
		  folder = root.Child("control-flow")
		  If Not folder.Exists Then QuitWithMessage("Missing `control-flow` folder (Dash.PopulateDatabase).")
		  For Each f In folder.Children
		    If f.Name <> "index.html" And f.Name <> "introduction.html" Then
		      
		      name = f.Name.Replace(".html", "")
		      type = kTypeKeyword
		      path = kBaseURL + "control-flow/" + f.Name
		      
		      db.SQLExecute("INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES " + _
		      "('" + name + "', '" + type + "', '" + path + "');")
		      If db.Error Then QuitWithMessage("Unable to insert record into database: " + db.ErrorMessage)
		    End If
		  Next f
		  
		  ' Data types.
		  folder = root.Child("data-types")
		  If Not folder.Exists Then QuitWithMessage("Missing `data-types` folder (Dash.PopulateDatabase).")
		  For Each f In folder.Children
		    If f.Name <> "index.html" And f.Name <> "introduction.html" And Not f.IsFolder Then
		      
		      name = f.Name.Replace(".html", "").TitleCase
		      type = kTypeType
		      path = kBaseURL + "data-types/" + f.Name
		      
		      db.SQLExecute("INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES " + _
		      "('" + name + "', '" + type + "', '" + path + "');")
		      If db.Error Then QuitWithMessage("Unable to insert record into database: " + db.ErrorMessage)
		    End If
		  Next f
		  
		  ' Standard library.
		  folder = root.Child("standard-library")
		  If Not folder.Exists Then QuitWithMessage("Missing `standard-library` folder (Dash.PopulateDatabase).")
		  For Each f In folder.Children
		    
		    If Not f.IsFolder Then Continue
		    
		    If f.Name = "modules" Then
		      
		      For Each f1 As Xojo.IO.FolderItem In f.Children
		        
		        If Not f1.IsFolder Then Continue
		        
		        ' f1 is a module folder.
		        ' Add the module.
		        name = f1.Name
		        moduleName = name
		        type = kTypeModule
		        path = kBaseURL + "standard-library/modules/" + name + "/introduction.html"
		        db.SQLExecute("INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES " + _
		        "('" + moduleName.Titlecase + "', '" + type + "', '" + path + "');")
		        If db.Error Then QuitWithMessage("Unable to insert record into database: " + db.ErrorMessage)
		        
		        ' Add properties (getters/setters) and methods.
		        For each f2 As Xojo.IO.FolderItem In f1.Children
		          ' Remember f1 is the module folder, f2 is an enclosing getter/setter/method folder.
		          If Not f2.IsFolder Then Continue
		          Select Case f2.Name
		          Case "getters"
		            For Each f3 As Xojo.IO.FolderItem In f2.Children
		              If f3.IsFolder Then Continue
		              If f3.Name <> "index.html" And f3.Name <> "introduction.html" Then
		                name = EntityNameFromHTMLFile(f3)
		                type = kTypeProperty
		                path = kBaseURL + "standard-library/" + moduleName + "/getters/" + f3.Name
		                db.SQLExecute("INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES " + _
		                "('" + name + "', '" + type + "', '" + path + "');")
		                If db.Error Then QuitWithMessage("Unable to insert record into database: " + db.ErrorMessage)
		              End If
		            Next f3
		          Case "setters"
		            For Each f3 As Xojo.IO.FolderItem In f2.Children
		              If f3.IsFolder Then Continue
		              If f3.Name <> "index.html" And f3.Name <> "introduction.html" Then
		                name = EntityNameFromHTMLFile(f3)
		                type = kTypeProperty
		                path = kBaseURL + "standard-library/" + moduleName + "/setters/" + f3.Name
		                db.SQLExecute("INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES " + _
		                "('" + name + "', '" + type + "', '" + path + "');")
		                If db.Error Then QuitWithMessage("Unable to insert record into database: " + db.ErrorMessage)
		              End If
		            Next f3
		          Case "methods"
		            For Each f3 As Xojo.IO.FolderItem In f2.Children
		              If f3.IsFolder Then Continue
		              If f3.Name <> "index.html" And f3.Name <> "introduction.html" Then
		                name = EntityNameFromHTMLFile(f3)
		                type = kTypeMethod
		                path = kBaseURL + "standard-library/" + moduleName + "/methods/" + f3.Name
		                db.SQLExecute("INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES " + _
		                "('" + name + "', '" + type + "', '" + path + "');")
		                If db.Error Then QuitWithMessage("Unable to insert record into database: " + db.ErrorMessage)
		              End If
		            Next f3
		          End Select
		        Next f2
		      Next f1
		    ElseIf f.Name = "all-objects" Then
		      ' Add properties (getters/setters) and methods.
		      For each f1 As Xojo.IO.FolderItem In f.Children
		        If Not f1.IsFolder Then Continue
		        Select Case f1.Name
		        Case "getters"
		          For Each f2 As Xojo.IO.FolderItem In f1.Children
		            If f2.IsFolder Then Continue
		            If f2.Name <> "index.html" And f2.Name <> "introduction.html" Then
		              name = EntityNameFromHTMLFile(f2)
		              type = kTypeProperty
		              path = kBaseURL + "standard-library/all-objects/getters/" + f2.Name
		              db.SQLExecute("INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES " + _
		              "('" + name + "', '" + type + "', '" + path + "');")
		              If db.Error Then QuitWithMessage("Unable to insert record into database: " + db.ErrorMessage)
		            End If
		          Next f2
		        Case "setters"
		          For Each f2 As Xojo.IO.FolderItem In f1.Children
		            If f2.IsFolder Then Continue
		            If f2.Name <> "index.html" And f2.Name <> "introduction.html" Then
		              name = EntityNameFromHTMLFile(f2)
		              type = kTypeProperty
		              path = kBaseURL + "standard-library/all-objects/setters/" + f2.Name
		              db.SQLExecute("INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES " + _
		              "('" + name + "', '" + type + "', '" + path + "');")
		              If db.Error Then QuitWithMessage("Unable to insert record into database: " + db.ErrorMessage)
		            End If
		          Next f2
		        Case "methods"
		          For Each f2 As Xojo.IO.FolderItem In f1.Children
		            If f2.IsFolder Then Continue
		            If f2.Name <> "index.html" And f2.Name <> "introduction.html" Then
		              name = EntityNameFromHTMLFile(f2)
		              type = kTypeMethod
		              path = kBaseURL + "standard-library/all-objects/methods/" + f2.Name
		              db.SQLExecute("INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES " + _
		              "('" + name + "', '" + type + "', '" + path + "');")
		              If db.Error Then QuitWithMessage("Unable to insert record into database: " + db.ErrorMessage)
		            End If
		          Next f2
		        End Select
		      Next f1
		    ElseIf f.Name = "global-functions" Then
		      For each f1 As Xojo.IO.FolderItem In f.Children
		        If f1.Name <> "index.html" And f1.Name <> "introduction.html" Then
		          name = EntityNameFromHTMLFile(f1)
		          type = kTypeGlobal
		          path = kBaseURL + "standard-library/global-functions/" + f1.Name
		          db.SQLExecute("INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES " + _
		          "('" + name + "', '" + type + "', '" + path + "');")
		          If db.Error Then QuitWithMessage("Unable to insert record into database: " + db.ErrorMessage)
		        End If
		      Next f1
		    Else ' A class folder.
		      ' Add the class.
		      name = f.Name.Replace(".html", "")
		      className = name
		      type = kTypeClass
		      path = kBaseURL + "standard-library/" + name + "/introduction.html"
		      db.SQLExecute("INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES " + _
		      "('" + className.Titlecase + "', '" + type + "', '" + path + "');")
		      If db.Error Then QuitWithMessage("Unable to insert record into database: " + db.ErrorMessage)
		      
		      ' Add properties (getters/setters) and methods.
		      For each f1 As Xojo.IO.FolderItem In f.Children
		        If Not f1.IsFolder Then Continue
		        Select Case f1.Name
		        Case "getters"
		          For Each f2 As Xojo.IO.FolderItem In f1.Children
		            If f2.IsFolder Then Continue
		            If f2.Name <> "index.html" And f2.Name <> "introduction.html" Then
		              name = EntityNameFromHTMLFile(f2)
		              type = kTypeProperty
		              path = kBaseURL + "standard-library/" + className + "/getters/" + f2.Name
		              db.SQLExecute("INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES " + _
		              "('" + name + "', '" + type + "', '" + path + "');")
		              If db.Error Then QuitWithMessage("Unable to insert record into database: " + db.ErrorMessage)
		            End If
		          Next f2
		        Case "setters"
		          For Each f2 As Xojo.IO.FolderItem In f1.Children
		            If f2.IsFolder Then Continue
		            If f2.Name <> "index.html" And f2.Name <> "introduction.html" Then
		              name = EntityNameFromHTMLFile(f2)
		              type = kTypeProperty
		              path = kBaseURL + "standard-library/" + className + "/setters/" + f2.Name
		              db.SQLExecute("INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES " + _
		              "('" + name + "', '" + type + "', '" + path + "');")
		              If db.Error Then QuitWithMessage("Unable to insert record into database: " + db.ErrorMessage)
		            End If
		          Next f2
		        Case "methods"
		          For Each f2 As Xojo.IO.FolderItem In f1.Children
		            If f2.IsFolder Then Continue
		            If f2.Name <> "index.html" And f2.Name <> "introduction.html" Then
		              name = EntityNameFromHTMLFile(f2)
		              type = kTypeMethod
		              path = kBaseURL + "standard-library/" + className + "/methods/" + f2.Name
		              db.SQLExecute("INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES " + _
		              "('" + name + "', '" + type + "', '" + path + "');")
		              If db.Error Then QuitWithMessage("Unable to insert record into database: " + db.ErrorMessage)
		            End If
		          Next f2
		        End Select
		      Next f1
		    End If
		  Next f
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub QuitWithMessage(message As String)
		  MsgBox(message)
		  Call FileSystem.ReallyDelete(DocsetRoot)
		  Quit
		End Sub
	#tag EndMethod


	#tag Property, Flags = &h1
		Protected db As SQLiteDatabase
	#tag EndProperty

	#tag Property, Flags = &h1
		Protected dbFile As FolderItem
	#tag EndProperty

	#tag Property, Flags = &h1
		Protected DocsetDocsRoot As FolderItem
	#tag EndProperty

	#tag Property, Flags = &h1
		Protected DocsetParent As FolderItem
	#tag EndProperty

	#tag Property, Flags = &h1
		Protected DocsetRoot As FolderItem
	#tag EndProperty

	#tag Property, Flags = &h1
		Protected SourceRoot As FolderItem
	#tag EndProperty


	#tag Constant, Name = kBaseURL, Type = String, Dynamic = False, Default = \"https://dash.roolang.org/docs/", Scope = Protected
	#tag EndConstant

	#tag Constant, Name = kDocsetName, Type = String, Dynamic = False, Default = \"Roo", Scope = Protected
	#tag EndConstant

	#tag Constant, Name = kTypeBuiltIn, Type = String, Dynamic = False, Default = \"Builtin", Scope = Protected
	#tag EndConstant

	#tag Constant, Name = kTypeClass, Type = String, Dynamic = False, Default = \"Class", Scope = Protected
	#tag EndConstant

	#tag Constant, Name = kTypeConstant, Type = String, Dynamic = False, Default = \"Constant", Scope = Protected
	#tag EndConstant

	#tag Constant, Name = kTypeConstructor, Type = String, Dynamic = False, Default = \"Constructor", Scope = Protected
	#tag EndConstant

	#tag Constant, Name = kTypeFunction, Type = String, Dynamic = False, Default = \"Function", Scope = Protected
	#tag EndConstant

	#tag Constant, Name = kTypeGlobal, Type = String, Dynamic = False, Default = \"Global", Scope = Protected
	#tag EndConstant

	#tag Constant, Name = kTypeInstance, Type = String, Dynamic = False, Default = \"Instance", Scope = Protected
	#tag EndConstant

	#tag Constant, Name = kTypeKeyword, Type = String, Dynamic = False, Default = \"Keyword", Scope = Protected
	#tag EndConstant

	#tag Constant, Name = kTypeLiteral, Type = String, Dynamic = False, Default = \"Literal", Scope = Protected
	#tag EndConstant

	#tag Constant, Name = kTypeMethod, Type = String, Dynamic = False, Default = \"Method", Scope = Protected
	#tag EndConstant

	#tag Constant, Name = kTypeModule, Type = String, Dynamic = False, Default = \"Module", Scope = Protected
	#tag EndConstant

	#tag Constant, Name = kTypeObject, Type = String, Dynamic = False, Default = \"Object", Scope = Protected
	#tag EndConstant

	#tag Constant, Name = kTypeOperator, Type = String, Dynamic = False, Default = \"Operator", Scope = Protected
	#tag EndConstant

	#tag Constant, Name = kTypeParameter, Type = String, Dynamic = False, Default = \"Paramater", Scope = Protected
	#tag EndConstant

	#tag Constant, Name = kTypeProperty, Type = String, Dynamic = False, Default = \"Property", Scope = Protected
	#tag EndConstant

	#tag Constant, Name = kTypeStatement, Type = String, Dynamic = False, Default = \"Statement", Scope = Protected
	#tag EndConstant

	#tag Constant, Name = kTypeType, Type = String, Dynamic = False, Default = \"Type", Scope = Protected
	#tag EndConstant

	#tag Constant, Name = kTypeValue, Type = String, Dynamic = False, Default = \"Value", Scope = Protected
	#tag EndConstant

	#tag Constant, Name = kTypeVariable, Type = String, Dynamic = False, Default = \"Variable", Scope = Protected
	#tag EndConstant


	#tag ViewBehavior
		#tag ViewProperty
			Name="Name"
			Visible=true
			Group="ID"
			Type="String"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Index"
			Visible=true
			Group="ID"
			InitialValue="-2147483648"
			Type="Integer"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Super"
			Visible=true
			Group="ID"
			Type="String"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Left"
			Visible=true
			Group="Position"
			InitialValue="0"
			Type="Integer"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Top"
			Visible=true
			Group="Position"
			InitialValue="0"
			Type="Integer"
		#tag EndViewProperty
	#tag EndViewBehavior
End Module
#tag EndModule
