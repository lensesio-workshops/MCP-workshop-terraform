output "student_environments" {
  description = "Student environment details"
  value = {
    for id, student in module.student : id => {
      namespace = student.namespace
      hq_url    = student.hq_url
      username  = student.admin_username
      password  = student.admin_password
    }
  }
  sensitive = true
}

output "student_urls" {
  description = "Student HQ URLs (non-sensitive)"
  value = {
    for id, student in module.student : "student${id}" => student.hq_url
  }
}
