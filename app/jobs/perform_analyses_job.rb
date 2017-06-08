class PerformAnalysesJob < ActiveJob::Base
  queue_as :default

  def perform(report)
    rails_best_practices_analysis = Analyses::RailsBestPracticesAnalysis.create!(report: report)
    model_diagram_analysis = Analyses::ModelDiagramAnalysis.create!(report: report)
    code_coverage_analysis = Analyses::CodeCoverageAnalysis.create!(report: report)
    
    connection = VMConnection.new(report)

    begin
      
      #Rails.logger.debug "\n\n ----- Executing rails_best_practices_analysis (PerformAnalysesJob) ... ----- \n\n"
      #rails_best_practices_analysis.run
      
      Rails.logger.debug "\n\n ----- Executing model_diagram_analysis (PerformAnalysesJob) ... ----- \n\n"
      model_diagram_analysis.run
            
      #Rails.logger.debug "\n\n ----- Executing code_coverage_analysis (PerformAnalysesJob) ... ----- \n\n"
      #code_coverage_analysis.run
      
      report.project.remove_github_hook(report) unless mark_as_analysed(report)
    rescue Exception
      puts Exception
      "Exception running analyses"
    end

    connection.execute_in_rails_app(["bundle exec rake db:drop"])
    # connection.delete_gemset
    # connection.delete_repository
  end

  private

  def mark_as_analysed(report)
    project = report.project

    unless last_report_analyses?(report)
      project.has_last_report_analyses = false
      project.save
      return false
    end

    project.has_last_report_analyses = true
    project.save
    project.create_github_hook unless project.github_webhook_id && Rails.env.development?
    true
  end

  def last_report_analyses?(report)
    return true # REMOVE THIS
    report.model_diagram_analysis.json_data? ||
      report.rails_best_practices_analysis.nbp_report ||
      report.rails_best_practices_analysis.score
  end
end
